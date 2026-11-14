// WeBoxHost.swift — iOS 侧最小宿主骨架（把 APK 的 JS 规则层原样跑起来）
//
// 这个 APK 的业务规则是纯 JS，只依赖 4 个 __native* 钩子：
//   __nativeSync(json) -> String?       同步桥接（40 个 method）
//   __nativeAsync(json) -> Promise      异步桥接（request / dom / compute / tmdb）
//   __nativeLog(json)                   日志
//   __nativeCryptoResource / __nativeHtmlResource / __nativeCheerioResource -> String(JS 源码)
//
// Android 用 QuickJS 实现这些钩子；iOS 用系统自带 JavaScriptCore 实现，无需带任何 .so。
// 编译环境：Xcode 15+ / Swift 5.9 / iOS 17+（WKWebView 可选，规则不一定需要 DOM）。
//
// 这不是完整 App，是可直接粘进 Xcode 工程的桥接层 + 播放器入口。
// 完整步骤见同目录 README.md。

import Foundation
import JavaScriptCore
import CryptoKit
import Security
import AVFoundation
import AVKit
import WebKit

// MARK: - 1. 桥接请求模型

struct BridgeRequest: Decodable {
    let method: String
    let params: [String: AnyDecodable]?
}

// 轻量 Any 解码（JSON 里 params 是异构字典）
struct AnyDecodable: Decodable {
    let value: Any
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = NSNull() }
        else if let b = try? c.decode(Bool.self) { value = b }
        else if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = s }
        else if let a = try? c.decode([AnyDecodable].self) { value = a.map { $0.value } }
        else if let o = try? c.decode([String: AnyDecodable].self) { value = o.mapValues { $0.value } }
        else { value = NSNull() }
    }
}

// MARK: - 2. 同步桥接实现（对应 bridge.json 的 sync 列表）

final class SyncBridge {
    let defaults = UserDefaults(suiteName: "group.dev.webox.app") ?? .standard
    let cache = NSCache<NSString, NSString>()
    var binaryHandles: [String: Data] = [:]

    func run(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let req = try? JSONDecoder().decode(BridgeRequest.self, from: data) else { return nil }
        let p: [String: Any] = (req.params ?? [:]).mapValues { $0.value }

        switch req.method {

        // --- 能力声明 ---
        case "runtime.capabilities":
            return json(["compute": true, "dom": true, "memoryHls": true,
                         "mediaProcessor": true, "binary": true, "protocol": "0.0.7"])

        // --- URL ---
        case "url.validate":
            let u = p["url"] as? String ?? ""
            let ok = u.hasPrefix("http://") || u.hasPrefix("https://")
            if ok { return json(u) }
            NSException(name: NSExceptionName("WeBoxBridge"), reason: "invalid url", userInfo: nil).raise()
            return nil
        case "url.resolve":
            let u = p["url"] as? String ?? "", base = p["base"] as? String ?? ""
            return json(URL(string: u, relativeTo: URL(string: base))?.absoluteString ?? u)
        case "url.origin":
            let u = p["url"] as? String ?? ""
            if let c = URLComponents(string: u), let h = c.host {
                return json((c.scheme ?? "https") + "://" + h + (c.port.map { ":\($0)" } ?? ""))
            }
            return json("")

        // --- 取消 / 缓存 ---
        case "native.cancelled":       return json(false)
        case "native.cache.generation": return json(1)
        case "native.cache.seconds":   return json(p["seconds"] as? Int ?? 3600)

        // --- 存储（widget.js 的 Widget.storage / sharedCache / webox.js 的 native.store） ---
        case "storage.getItem", "sharedCache.getItem", "native.store.get":
            let k = storeKey(req.method, p)
            return json(defaults.string(forKey: k) as Any)
        case "storage.setItem", "sharedCache.setItem", "native.store.set":
            defaults.set(p["value"] as? String ?? "", forKey: storeKey(req.method, p)); return nil
        case "storage.removeItem", "sharedCache.removeItem", "native.store.remove":
            defaults.removeObject(forKey: storeKey(req.method, p)); return nil
        case "storage.clear":
            for k in defaults.dictionaryRepresentation().keys { defaults.removeObject(forKey: k) }
            return nil
        case "storage.keys", "sharedCache.keys":
            let ns = (req.method.hasPrefix("shared") ? "sharedCache." : "storage.")
            return json(defaults.dictionaryRepresentation().keys
                .filter { $0.hasPrefix(ns) }.map { String($0.dropFirst(ns.count)) })

        // --- 编码 / 哈希（CommonCrypto） ---
        case "crypto.encode":  return cryptoEncode(p)
        case "crypto.random":
            let n = p["size"] as? Int ?? 0
            var b = [UInt8](repeating: 0, count: max(0, n))
            _ = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
            return json(b)
        case "crypto.hash":    return json(hash(p["text"] as? String ?? "", alg: p["algorithm"] as? String ?? "MD5"))
        case "crypto.hmac":    return json(hmac(p["text"] as? String ?? "", key: p["key"] as? String ?? "", alg: p["algorithm"] as? String ?? "SHA256"))
        case "crypto.aes":     return cryptoAES(p)
        case "crypto.rsa":     return json("")   // 用 SecKey 实现，按需补

        // --- binary.*（在内存里维护 Data 句柄，避免落盘） ---
        case "binary.size":     return json(binaryHandles[p["handle"] as? String ?? ""]?.count ?? 0)
        case "binary.read":     return binaryRead(p)
        case "binary.slice":    return binarySlice(p)
        case "binary.write":    return binaryWrite(p)
        case "binary.patch":    return binaryPatch(p)
        case "binary.concat":   return binaryConcat(p)

        case "i18n":           return json(p["value"] as? String ?? "")

        default:
            // request / tmdb / compute / dom 走异步侧；此处返回 nil 让 JS 侧按 async 处理
            return nil
        }
    }

    private func storeKey(_ m: String, _ p: [String: Any]) -> String {
        let k = p["key"] as? String ?? ""
        if m.hasPrefix("sharedCache") { return "sharedCache." + (p["namespace"] as? String ?? "") + "." + k }
        if m.hasPrefix("native.store") { return "storage." + k }
        return "storage." + k
    }

    private func json(_ v: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(v),
              let d = try? JSONSerialization.data(withJSONObject: v, options: []),
              let s = String(data: d, encoding: .utf8) else { return nil }
        return s
    }

    private func cryptoEncode(_ p: [String: Any]) -> String? {
        let text = p["text"] as? String ?? "", from = p["from"] as? String ?? "utf8", to = p["to"] as? String ?? "base64"
        let src: Data? = from == "base64" ? Data(base64Encoded: text)
            : from == "latin1" ? Data(text.utf8.map { UInt8($0 & 0xff) })
            : text.data(using: .utf8)
        guard let d = src else { return json("") }
        if to == "base64" { return json(d.base64EncodedString()) }
        if to == "latin1" { return json(String(bytes: d, encoding: .isoLatin1) ?? "") }
        return json(String(data: d, encoding: .utf8) ?? "")
    }

    private func hash(_ s: String, alg: String) -> String {
        let d = Data(s.utf8)
        switch alg.uppercased() {
        case "MD5":    return hex(Insecure.MD5.hash(data: d))
        case "SHA1":   return hex(Insecure.SHA1.hash(data: d))
        case "SHA256": return hex(SHA256.hash(data: d))
        case "SHA512": return hex(SHA512.hash(data: d))
        default: return ""
        }
    }
    private func hmac(_ s: String, key: String, alg: String) -> String {
        let k = SymmetricKey(data: Data(key.utf8)), m = Data(s.utf8)
        switch alg.uppercased() {
        case "SHA1", "HMACSHA1", "HMAC-SHA1":   return hex(HMAC<Insecure.SHA1>.authenticationCode(for: m, using: k))
        case "SHA512", "HMACSHA512", "HMAC-SHA512": return hex(HMAC<SHA512>.authenticationCode(for: m, using: k))
        default: return hex(HMAC<SHA256>.authenticationCode(for: m, using: k))
        }
    }
    private func hex<S: Sequence>(_ b: S) -> String where S.Element == UInt8 {
        b.map { String(format: "%02x", $0) }.joined()
    }

    private func cryptoAES(_ p: [String: Any]) -> String? {
        // widget.js 的 aesEncrypt/aesDecrypt：key/iv 为字符串，options 可含 mode/padding。
        // 完整实现用 CCCrypt(kCCAlgorithmAES128)，这里给出口位置；多数规则只用 hash/md5/base64。
        return json("")
    }

    private func binaryRead(_ p: [String: Any]) -> String? {
        guard let h = p["handle"] as? String, let d = binaryHandles[h] else { return json("") }
        let off = p["offset"] as? Int ?? 0, len = p["length"] as? Int ?? (d.count - off)
        let end = min(d.count, off + max(0, len))
        guard off <= end else { return json("") }
        return json(Data(d[off..<end]).base64EncodedString())
    }
    private func binarySlice(_ p: [String: Any]) -> String? {
        guard let h = p["handle"] as? String, let d = binaryHandles[h] else { return nil }
        let off = p["offset"] as? Int ?? 0, len = p["length"] as? Int ?? (d.count - off)
        let nh = "h\(binaryHandles.count)"; binaryHandles[nh] = Data(d[off..<min(d.count, off+len)])
        return json(nh)
    }
    private func binaryWrite(_ p: [String: Any]) -> String? {
        guard let h = p["handle"] as? String, let b64 = p["data"] as? String, let bytes = Data(base64Encoded: b64) else { return nil }
        var d = binaryHandles[h] ?? Data(); let off = p["offset"] as? Int ?? 0
        if d.count < off { d.append(Data(repeating: 0, count: off - d.count)) }
        d.replaceSubrange(off..<min(d.count, off+bytes.count), with: bytes); binaryHandles[h] = d
        return nil
    }
    private func binaryPatch(_ p: [String: Any]) -> String? {
        guard let h = p["handle"] as? String else { return nil }
        for patch in (p["patches"] as? [[String: Any]] ?? []) {
            _ = binaryWrite(["handle": h, "offset": patch["offset"] as? Int ?? 0, "data": patch["data"] as? String ?? ""])
        }
        return nil
    }
    private func binaryConcat(_ p: [String: Any]) -> String? {
        var out = Data()
        for h in (p["handles"] as? [String] ?? []) { if let d = binaryHandles[h] { out.append(d) } }
        let nh = "h\(binaryHandles.count)"; binaryHandles[nh] = out; return json(nh)
    }
}

// MARK: - 3. 异步桥接：request / dom / compute / tmdb

final class AsyncBridge {
    func run(_ raw: String) async throws -> String {
        guard let data = raw.data(using: .utf8),
              let req = try? JSONDecoder().decode(BridgeRequest.self, from: data) else { return "{}" }
        let p: [String: Any] = (req.params ?? [:]).mapValues { $0.value }

        switch req.method {
        case "request":                       return try await http(p)
        case "tmdb":                          return try await tmdb(p)
        case "dom.userAgent":                 return json(["userAgent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"])
        case "dom":                           return try await dom(p)
        case "compute":                       return try await compute(p)
        default:                              return "{}"
        }
    }

    private func http(_ p: [String: Any]) async throws -> String {
        guard let s = p["url"] as? String, let url = URL(string: s) else { return "{}" }
        var r = URLRequest(url: url)
        r.httpMethod = (p["method"] as? String)?.uppercased() ?? "GET"
        r.timeoutInterval = TimeInterval(p["timeout"] as? Double ?? p["timeoutMs"] as? Double ?? 20)
        for (k, v) in (p["headers"] as? [String: String] ?? [:]) { r.setValue(v, forHTTPHeaderField: k) }
        if let body = p["data"] as? String { r.httpBody = body.data(using: .utf8) }
        if let params = p["params"] as? [String: Any], var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            c.queryItems = params.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
            r.url = c.url
        }
        let (data, resp) = try await URLSession.shared.data(for: r)
        let h = resp as? HTTPURLResponse
        let decodable = p["decodable"] as? Bool ?? true
        let body: Any = decodable ? (String(data: data, encoding: .utf8) ?? "") : data.base64EncodedString()
        return json(["statusCode": h?.statusCode ?? 0, "status": h?.statusCode ?? 0,
                     "data": body, "body": body,
                     "headers": h?.allHeaderFields.reduce(into: [String: String]()) { $0["\($0.key)"] = "\($0.value)" } ?? [:],
                     "url": h?.url?.absoluteString ?? s])
    }

    private func tmdb(_ p: [String: Any]) async throws -> String {
        // APK 里有 3 个 TMDB 代理域名：api.themoviedb.org / tmdb.quswer.com / recommend.feifeiduck.com/tmdb
        let api = p["api"] as? String ?? ""
        let base = "https://api.themoviedb.org/3/"
        return try await http(["url": base + api.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                               "method": "GET", "params": p["params"] as? [String: Any] ?? [:]])
    }

    private func dom(_ p: [String: Any]) async throws -> String {
        // 对应 APK 的 assets/dom.html + dom-host.js：sandbox iframe 里 eval 规则代码，
        // 通过 postMessage 回传 {type:messageType, result:{...}}。iOS 用 WKWebView 复刻。
        let code = p["code"] as? String ?? p["codeBase64"].flatMap { b64 in
            Data(base64Encoded: b64 as? String ?? "").flatMap { String(data: $0, encoding: .utf8) }
        } ?? ""
        let msgType = p["messageType"] as? String ?? "webox:dom:result"
        let errType = p["errorType"] as? String ?? "webox:dom:error"
        let ua = p["userAgent"] as? String ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)"
        let boot = "try{(0,eval)(\(jsLiteral(code)))}catch(_){parent.postMessage({type:\(jsLiteral(errType))},'*')}"
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'; connect-src 'none'">
        </head><body><script>\(boot)</script></body></html>
        """
        // 实机在 WKWebView 里 loadHTMLString 并挂 WKScriptMessageHandler 收 messageType；
        // 这里返回结构化占位，接入点已留好（见 README §DOM）。
        return json(["ok": true, "value": ["result": [:], "viewport": [390, 844], "userAgent": ua]])
    }

    private func compute(_ p: [String: Any]) async throws -> String {
        // 对应 compute.html + compute-worker.js：另起一个 JSContext 跑 request.code(input,binaries)
        let code = p["code"] as? String ?? "()=>null"
        let ctx = JSContext()!
        ctx.evaluateScript("var __r = (" + code + ")(__input, __binaries); JSON.stringify({ok:true,value:__r})")
        return ctx.objectForKeyedSubscript("__r").toString() ?? "{\"ok\":false}"
    }

    private func jsLiteral(_ s: String) -> String {
        (try? JSONSerialization.data(withJSONObject: [s], options: []))
            .flatMap { String(data: $0, encoding: .utf8) }
            .map { String($0.dropFirst().dropLast()) } ?? "''"
    }
    private func json(_ v: Any) -> String {
        guard JSONSerialization.isValidJSONObject(v),
              let d = try? JSONSerialization.data(withJSONObject: v),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }
}

// MARK: - 4. JSRuntime：把 4 个 __native* 钩子注入 JSContext，按依赖顺序加载 runtime/*.js

final class JSRuntime {
    let ctx = JSContext()!
    let sync = SyncBridge()
    let async = AsyncBridge()
    var bundle: Bundle { .main }

    init() {
        ctx.exceptionHandler = { _, e in print("[WeBox JS exception]", e?.toString() ?? "") }

        // __nativeSync — 同步，返回 String?
        let syncFn: @convention(block) (String) -> String? = { [weak self] raw in
            self?.sync.run(raw)
        }
        ctx.setObject(syncFn, forKeyedSubscript: "__nativeSync" as NSString)

        // __nativeAsync — 返回 JS Promise（Swift Task 完成后 resolve）
        // 注意：JSContext 非 Sendable，Swift 6 严格并发下把本类标 @unchecked Sendable 或关闭 Strict Concurrency。
        let asyncFn: @convention(block) (String) -> JSValue = { [weak self] raw in
            guard let self = self else { return JSValue(undefinedIn: JSContext())! }
            let ctx = self.ctx, bridge = self.async, quote = self.jsQuote
            let promise = ctx.evaluateScript(
                "new Promise(function(res,rej){globalThis.__wbRes=res;globalThis.__wbRej=rej;})")!
            Task {
                do {
                    let s = try await bridge.run(raw)
                    await MainActor.run { ctx.evaluateScript("__wbRes(" + quote(s) + ")") }
                } catch {
                    await MainActor.run { ctx.evaluateScript("__wbRej(" + quote(error.localizedDescription) + ")") }
                }
            }
            return promise
        }
        ctx.setObject(asyncFn, forKeyedSubscript: "__nativeAsync" as NSString)

        let logFn: @convention(block) (String) -> Void = { print("[WeBox]", $0) }
        ctx.setObject(logFn, forKeyedSubscript: "__nativeLog" as NSString)

        // 三个资源钩子返回 JS 源码字符串（对应 APK 里 CryptoJS / cheerio / html 资源）
        for (hook, file) in ["__nativeCryptoResource": "cryptojs",
                             "__nativeHtmlResource": "cheerio",
                             "__nativeCheerioResource": "cheerio"] {
            let src = resource(file)
            let fn: @convention(block) (String) -> String = { _ in src }
            ctx.setObject(fn, forKeyedSubscript: hook as NSString)
        }
    }

    private func jsQuote(_ s: String) -> String {
        (try? JSONSerialization.data(withJSONObject: [s])).flatMap { String(data: $0, encoding: .utf8) }
            .map { String($0.dropFirst().dropLast()) } ?? "''"
    }

    private func resource(_ name: String) -> String {
        guard let u = bundle.url(forResource: name, withExtension: "js", subdirectory: "runtime"),
              let s = try? String(contentsOf: u, encoding: .utf8) else { return "" }
        return s
    }

    /// 加载顺序与 APK 一致：cryptojs → cheerio → widget → xptv → webox
    func loadRuntime() {
        for n in ["cryptojs", "cheerio", "widget", "xptv", "webox"] {
            ctx.evaluateScript(resource(n), withSourceURL: URL(string: "webox://runtime/" + n + ".js"))
            print("[WeBox] loaded", n + ".js")
        }
    }

    /// 加载一个模块 .js 并读回它的 WidgetMetadata / WeBox.define 元数据
    func loadModule(_ js: String) -> String {
        ctx.evaluateScript(js)
        return ctx.evaluateScript("JSON.stringify(typeof __weboxMetadata==='function'?JSON.parse(__weboxMetadata()):null)")?.toString() ?? "null"
    }

    /// 调用模块导出函数（widget.js 的 __weboxInvoke）
    func invoke(name: String, argsJSON: String) async -> String {
        ctx.evaluateScript("globalThis.__wbPending = __weboxInvoke(\(jsQuote(name)), \(jsQuote(argsJSON)));")
        // __weboxInvoke 是 async，返回 Promise；用 await 语义在 JS 侧解开
        let v = ctx.evaluateScript("(async()=>await globalThis.__wbPending)()")
        return v?.toString() ?? "null"
    }
}

// MARK: - 5. 播放器入口：拿到 JS 规则吐出的直链后走 AVPlayer

final class WeBoxPlayerViewController: AVPlayerViewController {
    static func present(url: String, headers: [String: String] = [:], from vc: UIViewController) {
        guard let u = URL(string: url) else { return }
        var assetOpts: [String: Any] = [:]
        if !headers.isEmpty { assetOpts["AVURLAssetHTTPHeaderFieldsKey"] = headers }
        let asset = AVURLAsset(url: u, options: assetOpts)
        let playerVC = WeBoxPlayerViewController()
        playerVC.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        vc.present(playerVC, animated: true) { playerVC.player?.play() }
    }
}

// MARK: - 6. 使用示例（粘进 AppDelegate / SwiftUI .task）

func weboxBootExample() async {
    let rt = JSRuntime()
    rt.loadRuntime()
    if let url = Bundle.main.url(forResource: "demo", withExtension: "js", subdirectory: "modules"),
       let js = try? String(contentsOf: url, encoding: .utf8) {
        print("[WeBox] metadata:", rt.loadModule(js))
        let list = await rt.invoke(name: "loadList", argsJSON: "{\"group\":\"all\"}")
        print("[WeBox] list:", list)
        // 解析 list → 用户点选 → loadResource 拿直链 → WeBoxPlayerViewController.present
    }
}
