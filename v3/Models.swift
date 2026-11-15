import UIKit
import Foundation
import CryptoKit

func jsonText(_ value: Any) -> String { String(data: (try? JSONSerialization.data(withJSONObject:value, options:[.fragmentsAllowed])) ?? Data(), encoding:.utf8) ?? "null" }
func jsonValue(_ text:String) -> Any? { text.data(using:.utf8).flatMap { try? JSONSerialization.jsonObject(with:$0,options:[.fragmentsAllowed]) } }
struct Source: Codable {
    var id:String; var title:String; var kind:String; var location:String; var logo:String = ""; var builtin:Bool = false
}
struct ImportResult { var added:[Source] = []; var failed:[String] = [] }
struct WBError: LocalizedError { var message:String; var errorDescription:String? { message } }

@MainActor final class Library {
    static let shared = Library()
    let folder:URL
    var sources:[Source] = []
    var selected:String { get { UserDefaults.standard.string(forKey:"selectedSource") ?? "tmdb" } set { UserDefaults.standard.set(newValue,forKey:"selectedSource") } }
    var favorites:[[String:Any]] { get { (UserDefaults.standard.array(forKey:"wbFavorites") as? [[String:Any]]) ?? [] } set { UserDefaults.standard.set(newValue,forKey:"wbFavorites") } }
    init() {
        folder = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("Sources")
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        if let data = try? Data(contentsOf:folder.appendingPathComponent("library.json")),let saved = try? JSONDecoder().decode([Source].self,from:data) { sources=saved }
        if sources.isEmpty {
            sources=[Source(id:"tmdb",title:"TMDB",kind:"library",location:"",builtin:true),Source(id:"podcasts",title:"播客",kind:"podcast",location:"podcasts.webox",builtin:true),Source(id:"radio",title:"电台",kind:"radio",location:"radio.webox",builtin:true)]
            save()
        }
    }
    func save() { if let d=try? JSONEncoder().encode(sources) { try? d.write(to:folder.appendingPathComponent("library.json"),options:.atomic) }; NotificationCenter.default.post(name:Notification.Name("libraryChanged"),object:nil) }
    func count(_ kind:String)->Int { sources.filter{$0.kind==kind}.count }
    func source(_ id:String)->Source? { sources.first{$0.id==id} }
    func remove(_ id:String) { sources.removeAll{$0.id==id && !$0.builtin}; if selected==id {selected="tmdb"};save() }
    func code(_ s:Source) throws ->String {
        if s.builtin { guard let u=Bundle.main.url(forResource:s.location,withExtension:"js",subdirectory:"modules") else {throw WBError(message:"缺少内置脚本")};return try String(contentsOf:u,encoding:.utf8) }
        return try String(contentsOf:folder.appendingPathComponent(s.location),encoding:.utf8)
    }
    func content(_ url:URL) async throws ->String {
        let d:Data
        if url.isFileURL { let access=url.startAccessingSecurityScopedResource();defer {if access {url.stopAccessingSecurityScopedResource()}};d=try Data(contentsOf:url) }
        else { var q=URLRequest(url:url);q.timeoutInterval=30;let (data,r)=try await URLSession.shared.data(for:q);guard let h=r as? HTTPURLResponse,(200...299).contains(h.statusCode) else {throw WBError(message:"下载失败：HTTP \((r as? HTTPURLResponse)?.statusCode ?? 0)")};d=data }
        guard d.count<=2*1024*1024 else {throw WBError(message:"文件超过 2 MB 限制")}
        guard let s=String(data:d,encoding:.utf8) else {throw WBError(message:"文件不是 UTF-8 文本")};return s
    }
    func importURL(_ url:URL,kind:String="auto",name:String="",logo:String="") async ->ImportResult {
        var result=ImportResult()
        do {
            let text=try await content(url)
            if let o=jsonValue(text) as? [String:Any],let entries=(o["widgets"] as? [[String:Any]]) ?? (o["sources"] as? [[String:Any]]) ?? (o["vods"] as? [[String:Any]]) {
                guard entries.count<=100 else {throw WBError(message:"来源合集最多支持 100 项")}
                for entry in entries {
                    guard entry["enabled"] as? Bool != false else {continue}
                    let title=(entry["title"] as? String) ?? (entry["name"] as? String) ?? "未命名来源"
                    guard let path=entry["url"] as? String,let next=URL(string:path,relativeTo:url)?.absoluteURL else {result.failed.append(title+"：地址无效");continue}
                    do { let body=try await content(next);let s=try await add(body,url:next,kind:(entry["type"] as? String) ?? kind,name:title,logo:(entry["logo"] as? String) ?? logo);result.added.append(s) }
                    catch {result.failed.append(title+"："+error.localizedDescription)}
                }
            } else { result.added.append(try await add(text,url:url,kind:kind,name:name,logo:logo)) }
            save()
        } catch {result.failed.append(error.localizedDescription)}
        return result
    }
    func add(_ text:String,url:URL,kind:String,name:String,logo:String) async throws ->Source {
        let t=text.trimmingCharacters(in:.whitespacesAndNewlines);var detected="";var title=name;var declaredIcon=logo
        if t.hasPrefix("#EXTM3U") {detected="m3u"}
        else if let o=jsonValue(t) as? [String:Any] {
            if o["class"] != nil && o["list"] != nil {detected="vod"}
            else if o["vod_node"] != nil && o["category"] != nil {detected="json"}
        }
        if t.contains("WidgetMetadata") || t.range(of:"WeBox\\s*\\.\\s*define\\s*\\(",options:.regularExpression) != nil || t.contains("getPlayinfo") {
            detected="js"
            let rt=JSRuntime();rt.loadRuntime();let raw=rt.loadModule(text)
            guard let meta=jsonValue(raw) as? [String:Any],let moduleID=meta["id"] as? String,!moduleID.isEmpty else {throw WBError(message:"脚本缺少有效的模块元数据")}
            if title.isEmpty {title=meta["title"] as? String ?? url.lastPathComponent}
            detected=meta["sourceCategory"] as? String ?? "js"
            if declaredIcon.isEmpty {declaredIcon=meta["icon"] as? String ?? ""}
        }
        guard !detected.isEmpty else {throw WBError(message:"未识别的内容，请选择网页规则、JS 脚本、VOD 接口、M3U 直播或来源合集")}
        if kind != "auto" && kind != detected && !(kind=="js" && ["podcast","radio"].contains(detected)) {throw WBError(message:"内容识别为 \(detected)，与选择的类别不一致")}
        let id=SHA256.hash(data:Data(url.absoluteString.utf8)).map{String(format:"%02x",$0)}.joined()
        let file=id+".txt";try text.write(to:folder.appendingPathComponent(file),atomically:true,encoding:.utf8)
        let source=Source(id:id,title:title.isEmpty ? url.deletingPathExtension().lastPathComponent:title,kind:detected,location:file,logo:declaredIcon)
        sources.removeAll{$0.id==id};sources.append(source);return source
    }
}

@MainActor final class ModuleSession {
    let runtime=JSRuntime();let source:Source;var metadata:[String:Any]=[:];var parameters:[String:Any]=[:]
    init(_ s:Source)throws { source=s;runtime.loadRuntime();metadata=(jsonValue(runtime.loadModule(try Library.shared.code(s))) as? [String:Any]) ?? [:];guard !metadata.isEmpty else {throw WBError(message:"读取脚本元数据失败")} }
    var native:Bool {metadata["hostProtocol"] as? String == "webox"}
    var listFunction:String { (metadata["modules"] as? [[String:Any]])?.first(where:{$0["type"] as? String != "stream"})?["functionName"] as? String ?? "loadList" }
    func request(_ name:String,_ argument:Any) async throws ->Any {
        let raw=await runtime.invoke(name:name,argsJSON:jsonText([argument]))
        guard let result=jsonValue(raw) else {throw WBError(message:"脚本返回非 JSON 数据")}
        if let o=result as? [String:Any],let e=o["__error__"] as? String {throw WBError(message:e)}
        return result
    }
    func list(_ query:String?=nil) async throws ->[[String:Any]] {
        let mods=(metadata["modules"] as? [[String:Any]]) ?? []
        let list=mods.first(where:{$0["type"] as? String != "stream"}) ?? [:]
        var p=parameters
        for param in (list["params"] as? [[String:Any]]) ?? [] {
            guard let name=param["name"] as? String,p[name]==nil else {continue}
            if let v=param["value"] {p[name]=v}
            else if let options=param["enumOptions"] as? [[String:Any]],let first=options.first {p[name]=first["value"]}
        }
        p["page"]=1;p["__wb_page"]=1;p["__wb_surface"]="browse"
        var fn=listFunction
        if let q=query {p["keyword"]=q;fn=(metadata["search"] as? [String:Any])?["functionName"] as? String ?? "search"}
        let r=try await request(fn,p)
        return (r as? [[String:Any]]) ?? ((r as? [String:Any])?["items"] as? [[String:Any]]) ?? []
    }
    func detail(_ item:[String:Any]) async throws ->[[String:Any]] {
        guard let link=item["link"] as? String else {return []}
        let r=try await request(native ? "__wbDetail":"loadDetail",link)
        return ((r as? [String:Any])?["childItems"] as? [[String:Any]]) ?? []
    }
    func play(_ item:[String:Any]) async throws ->[[String:Any]] {
        if let url=item["videoUrl"] as? String,url.hasPrefix("http") {return [["url":url,"headers":item["headers"] ?? [:]]]}
        let fn=(metadata["modules"] as? [[String:Any]])?.first(where:{$0["type"] as? String == "stream"})?["functionName"] as? String ?? "loadResource"
        let r=try await request(fn,["link":item["link"] ?? item["id"] ?? ""])
        return (r as? [[String:Any]]) ?? []
    }
}
