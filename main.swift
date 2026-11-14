// main.swift — WeBox iOS 免费壳的完整 UI：导入模块订阅 → 列片源 → 点击播放
// 纯 UIKit，避免 SwiftUI 并发/属性包装在云编译里的不确定性。
import UIKit
import Foundation
import AVKit

// MARK: - 全局引擎（单例，JSContext 只建一次、runtime 只加载一次）

@MainActor
final class AppEngine {
    static let shared = AppEngine()
    let rt = JSRuntime()
    var runtimeLoaded = false

    func ensureRuntime() {
        guard !runtimeLoaded else { return }
        rt.loadRuntime()
        runtimeLoaded = true
    }

    func bundleModules() -> [ModuleItem] {
        var out: [ModuleItem] = []
        for n in ["demo", "podcasts.webox", "radio.webox"] {
            if let u = Bundle.main.url(forResource: n, withExtension: "js", subdirectory: "modules") {
                out.append(ModuleItem(id: n, title: displayName(n), jsURL: u, isLocal: true))
            }
        }
        return out
    }

    private func displayName(_ n: String) -> String {
        if n == "demo" { return "公开示例 · Big Buck Bunny" }
        if n.hasPrefix("podcasts") { return "播客 Podcast" }
        if n.hasPrefix("radio") { return "电台 Radio" }
        return n
    }

    func loadJS(_ item: ModuleItem, completion: @escaping (String) -> Void) {
        ensureRuntime()
        if item.isLocal, let s = try? String(contentsOf: item.jsURL, encoding: .utf8) {
            completion(rt.loadModule(s))
        } else {
            URLSession.shared.dataTask(with: item.jsURL) { data, _, _ in
                let s = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                DispatchQueue.main.async { completion(self.rt.loadModule(s)) }
            }.resume()
        }
    }

    func call(_ fn: String, arg: [String: Any]) async -> [[String: Any]] {
        ensureRuntime()
        let argsJSON: String
        if let d = try? JSONSerialization.data(withJSONObject: [arg]),
           let s = String(data: d, encoding: .utf8) { argsJSON = s } else { argsJSON = "[{}]" }
        let out = await rt.invoke(name: fn, argsJSON: argsJSON)
        guard let d = out.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return [] }
        return arr
    }
}

struct ModuleItem {
    let id: String
    let title: String
    let jsURL: URL
    let isLocal: Bool
    var fnList: String = "loadList"
    var fnSearch: String = "search"
    var fnPlay: String = "loadResource"
}

// MARK: - 片源列表 VC

@MainActor
final class ItemsVC: UITableViewController {
    var module: ModuleItem!
    var items: [[String: Any]] = []
    var status = "加载中…"

    override func viewDidLoad() {
        super.viewDidLoad()
        title = module.title
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        let search = UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(doSearch))
        navigationItem.rightBarButtonItem = search
        Task { await reload(arg: [:]) }
    }

    @objc func doSearch() {
        let a = UIAlertController(title: "搜索", message: nil, preferredStyle: .alert)
        a.addTextField { $0.placeholder = "关键词" }
        a.addAction(UIAlertAction(title: "搜索", style: .default) { _ in
            let q = a.textFields?.first?.text ?? ""
            Task { await self.reload(arg: ["keyword": q, "query": q], fn: self.module.fnSearch) }
        })
        a.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(a, animated: true)
    }

    func reload(arg: [String: Any], fn: String? = nil) async {
        status = "加载中…"; tableView.reloadData()
        let f = fn ?? module.fnList
        let got = await AppEngine.shared.call(f, arg: arg)
        items = got
        status = got.isEmpty ? "无结果（模块可能用别的函数名，见控制台）" : "共 \(got.count) 条 · 点击播放"
        tableView.reloadData()
        print("[WeBox] \(f) -> \(got.count) items")
    }

    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { max(1, items.count) }
    override func tableView(_ t: UITableView, titleForHeaderInSection s: Int) -> String? { status }
    override func tableView(_ t: UITableView, cellForRowAt i: IndexPath) -> UITableViewCell {
        let c = t.dequeueReusableCell(withIdentifier: "c", for: i)
        if items.isEmpty { c.textLabel?.text = status; c.textLabel?.numberOfLines = 0; return c }
        let it = items[i.row]
        c.textLabel?.text = (it["title"] as? String) ?? (it["name"] as? String) ?? (it["vod_name"] as? String) ?? "(无标题)"
        c.textLabel?.numberOfLines = 2
        c.detailTextLabel?.text = (it["description"] as? String) ?? (it["subtitle"] as? String) ?? ""
        c.accessoryType = .disclosureIndicator
        return c
    }
    override func tableView(_ t: UITableView, didSelectRowAt i: IndexPath) {
        t.deselectRow(at: i, animated: true)
        guard !items.isEmpty else { return }
        let it = items[i.row]
        Task { await play(it) }
    }

    func play(_ it: [String: Any]) async {
        // 直链优先：模块若直接给 videoUrl/url 就不必再调 loadResource
        if let direct = it["videoUrl"] as? String, direct.hasPrefix("http") {
            presentPlayer(direct); return
        }
        let link = (it["link"] as? String) ?? (it["id"] as? String) ?? (it["vod_id"] as? String) ?? ""
        let res = await AppEngine.shared.call(module.fnPlay, arg: ["link": link])
        var streamURL: String?
        for r in res {
            if let u = r["url"] as? String, u.hasPrefix("http") { streamURL = u; break }
        }
        if let u = streamURL { presentPlayer(u) }
        else { toast("没拿到播放直链（模块可能需要特殊参数，见控制台）") }
    }

    func presentPlayer(_ u: String) {
        WeBoxPlayerViewController.present(url: u, from: self)
    }
    func toast(_ m: String) {
        let a = UIAlertController(title: nil, message: m, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "好", style: .default))
        present(a, animated: true)
    }
}

// MARK: - 模块列表 VC（首页）

@MainActor
final class RootVC: UITableViewController {
    var modules: [ModuleItem] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "WeBox · 免费壳"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "m")
        modules = AppEngine.shared.bundleModules()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addModule))
        let info = UILabel(frame: CGRect(x: 16, y: 0, width: view.bounds.width - 32, height: 96))
        info.numberOfLines = 0
        info.font = .systemFont(ofSize: 12)
        info.textColor = .secondaryLabel
        info.text = "内置 3 个模块。点右上角 + 粘贴 Widget 模块 .js 直链或 Rex 订阅 widgets.json 即可导入你自己的片源。规则在 JavaScriptCore 里跑，无付费墙。"
        tableView.tableHeaderView = info
    }

    @objc func addModule() {
        let a = UIAlertController(title: "导入模块 / 订阅", message: "粘贴 .js 模块直链，或 Rex 的 widgets.json 订阅地址", preferredStyle: .alert)
        a.addTextField { $0.placeholder = "https://…/module.js 或 widgets.json" }
        a.addAction(UIAlertAction(title: "导入", style: .default) { _ in
            guard let s = a.textFields?.first?.text, let u = URL(string: s) else { return }
            self.importURL(u)
        })
        a.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(a, animated: true)
    }

    func importURL(_ u: URL) {
        URLSession.shared.dataTask(with: u) { data, _, err in
            guard let data = data, let text = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { self.toast("下载失败: \(err?.localizedDescription ?? "")") }; return
            }
            DispatchQueue.main.async {
                // 订阅清单（widgets.json / .fwd）：解析 widgets[] 数组逐个加入
                if let d = text.data(using: .utf8),
                   let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                   let ws = obj["widgets"] as? [[String: Any]] {
                    var added = 0
                    for w in ws {
                        if let urlStr = w["url"] as? String, let ju = URL(string: urlStr) {
                            let title = (w["title"] as? String) ?? (w["id"] as? String) ?? "模块"
                            self.modules.append(ModuleItem(id: (w["id"] as? String) ?? ju.lastPathComponent,
                                                           title: title, jsURL: ju, isLocal: false))
                            added += 1
                        }
                    }
                    self.tableView.reloadData(); self.toast("订阅导入 \(added) 个模块")
                } else {
                    // 单个 .js 模块
                    let title = u.lastPathComponent
                    self.modules.append(ModuleItem(id: title, title: title, jsURL: u, isLocal: false))
                    self.tableView.reloadData(); self.toast("已导入 1 个模块")
                }
            }
        }.resume()
    }

    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { modules.count }
    override func tableView(_ t: UITableView, cellForRowAt i: IndexPath) -> UITableViewCell {
        let c = t.dequeueReusableCell(withIdentifier: "m", for: i)
        let m = modules[i.row]
        c.textLabel?.text = m.title
        c.detailTextLabel?.text = m.isLocal ? "内置" : m.jsURL.host ?? ""
        c.accessoryType = .disclosureIndicator
        return c
    }
    override func tableView(_ t: UITableView, didSelectRowAt i: IndexPath) {
        t.deselectRow(at: i, animated: true)
        let m = modules[i.row]
        AppEngine.shared.loadJS(m) { meta in
            print("[WeBox] metadata for \(m.id):", meta.prefix(300))
            // 从 metadata 猜函数名（demo.js: loadList/search/loadResource；xptv 契约: getCards/getTracks/getPlayinfo）
            var item = m
            if let d = meta.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                if let mods = o["modules"] as? [[String: Any]] {
                    for x in mods {
                        if let fn = x["functionName"] as? String {
                            let typ = (x["type"] as? String) ?? ""
                            if typ == "stream" { item.fnPlay = fn } else { item.fnList = fn }
                        }
                    }
                }
                if let sr = o["search"] as? [String: Any], let fn = sr["functionName"] as? String { item.fnSearch = fn }
                if let ttl = o["title"] as? String { item = ModuleItem(id: item.id, title: ttl, jsURL: item.jsURL,
                                                                        isLocal: item.isLocal, fnList: item.fnList,
                                                                        fnSearch: item.fnSearch, fnPlay: item.fnPlay) }
            }
            let vc = ItemsVC(style: .insetGrouped)
            vc.module = item
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }
    func toast(_ m: String) {
        let a = UIAlertController(title: nil, message: m, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "好", style: .default)); present(a, animated: true)
    }
}

// MARK: - App 入口

final class AppDelegate: NSObject, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let nav = UINavigationController(rootViewController: RootVC(style: .insetGrouped))
        nav.navigationBar.prefersLargeTitles = true
        window?.rootViewController = nav
        window?.makeKeyAndVisible()
        return true
    }
    // 支持从「文件」/浏览器把 .js、.json、rex://widget 分享进来
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if let nav = window?.rootViewController as? UINavigationController,
           let root = nav.viewControllers.first as? RootVC {
            if url.isFileURL { root.importURL(url) }
            else if let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
                    let q = c.queryItems?.first(where: { $0.name == "url" })?.value,
                    let u = URL(string: q) { root.importURL(u) }
            return true
        }
        return false
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
