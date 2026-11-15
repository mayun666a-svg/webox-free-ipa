// main.swift — 按 WeBox 原版截图重做：深色近黑 + 圆角分组卡片的「设置 / 内容源管理」界面
// 纯 UIKit。JS 规则引擎与播放链路保持不变（WeBoxHost.swift）。
import UIKit
import Foundation

// MARK: - 主题（对齐截图：近黑底 / 卡片 / 洋红主色）

enum Theme {
    static let bg     = UIColor(red: 0.09,  green: 0.075, blue: 0.095, alpha: 1)
    static let card   = UIColor(red: 0.155, green: 0.135, blue: 0.16,  alpha: 1)
    static let cardHi = UIColor(red: 0.21,  green: 0.185, blue: 0.215, alpha: 1)
    static let text   = UIColor.white
    static let sub    = UIColor(red: 0.62,  green: 0.60,  blue: 0.63,  alpha: 1)
    static let accent = UIColor(red: 0.92,  green: 0.35,  blue: 0.62,  alpha: 1)
    static let sep    = UIColor(white: 1, alpha: 0.06)
}

func avatarColor(_ key: String) -> UIColor {
    let p: [UIColor] = [
        UIColor(red: 0.20, green: 0.55, blue: 0.85, alpha: 1),
        UIColor(red: 0.85, green: 0.42, blue: 0.30, alpha: 1),
        UIColor(red: 0.35, green: 0.72, blue: 0.55, alpha: 1),
        UIColor(red: 0.62, green: 0.42, blue: 0.85, alpha: 1),
        UIColor(red: 0.88, green: 0.68, blue: 0.25, alpha: 1),
        UIColor(red: 0.30, green: 0.68, blue: 0.72, alpha: 1),
        UIColor(red: 0.85, green: 0.35, blue: 0.55, alpha: 1),
    ]
    var h = 0
    for u in key.unicodeScalars { h = (h &* 31 &+ Int(u.value)) & 0x7fffffff }
    return p[h % p.count]
}

// 生成一张彩色字母方块头像（对齐图3那排带字母的彩色图标）
func avatarImage(_ key: String, size: CGFloat = 34) -> UIImage {
    let r = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    return r.image { ctx in
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        avatarColor(key).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: size * 0.26).fill()
        let letters = key.filter { $0.isLetter || $0.isNumber }
        let t = String(letters.isEmpty ? "W" : String(letters.prefix(2))).uppercased() as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: size * 0.38),
            .foregroundColor: UIColor.white,
        ]
        let ts = t.size(withAttributes: attrs)
        t.draw(in: CGRect(x: (size - ts.width) / 2, y: (size - ts.height) / 2,
                          width: ts.width, height: ts.height), withAttributes: attrs)
    }
}

// MARK: - 全局引擎

final class AppEngine {
    static let shared = AppEngine()
    let rt = JSRuntime()
    var runtimeLoaded = false
    var sources: [ModuleItem] = []

    func ensureRuntime() {
        guard !runtimeLoaded else { return }
        rt.loadRuntime(); runtimeLoaded = true; seedBuiltins()
    }
    func seedBuiltins() {
        guard sources.isEmpty else { return }
        for n in ["demo", "podcasts.webox", "radio.webox"] {
            if let u = Bundle.main.url(forResource: n, withExtension: "js", subdirectory: "modules") {
                sources.append(ModuleItem(id: n, title: displayName(n), jsURL: u, isLocal: true, group: "内置 JS 内容源"))
            }
        }
        for nm in ["TMDB", "播客", "电台", "4k影视", "HStream", "MissAV", "ONE",
                   "SupJAV", "girigiri 动漫", "瓜子", "磁力熊", "肉视频"] {
            sources.append(ModuleItem(id: nm, title: nm,
                                      jsURL: URL(string: "webox://placeholder/" + nm.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!,
                                      isLocal: false, group: "示例 · 需导入真实模块"))
        }
    }
    func displayName(_ n: String) -> String {
        n == "demo" ? "公开示例 · Big Buck Bunny" : n.hasPrefix("podcasts") ? "播客" : n.hasPrefix("radio") ? "电台" : n
    }
    func loadJS(_ item: ModuleItem, completion: @escaping (String) -> Void) {
        ensureRuntime()
        if item.isLocal, let s = try? String(contentsOf: item.jsURL, encoding: .utf8) { completion(rt.loadModule(s)) }
        else if item.jsURL.scheme == "webox" { completion("null") }
        else {
            URLSession.shared.dataTask(with: item.jsURL) { d, _, _ in
                let s = d.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                DispatchQueue.main.async { completion(self.rt.loadModule(s)) }
            }.resume()
        }
    }
    func call(_ fn: String, arg: [String: Any]) async -> [[String: Any]] {
        ensureRuntime()
        let aj = (try? String(data: JSONSerialization.data(withJSONObject: [arg]), encoding: .utf8)) ?? "[{}]"
        let out = await rt.invoke(name: fn, argsJSON: aj)
        guard let d = out.data(using: .utf8),
              let a = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return [] }
        return a
    }
}

struct ModuleItem {
    let id: String; let title: String; let jsURL: URL; let isLocal: Bool
    var group: String = "JS 内容源"
    var fnList = "loadList"; var fnSearch = "search"; var fnPlay = "loadResource"
}

// MARK: - 深色分组卡片基类（用 .subtitle 样式让副标题显示）

class DarkTableVC: UITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.bg; tableView.backgroundColor = Theme.bg
        tableView.separatorColor = Theme.sep
        overrideUserInterfaceStyle = .dark
    }
    func cell(_ id: String) -> UITableViewCell {
        let c = tableView.dequeueReusableCell(withIdentifier: id)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: id)
        c.backgroundColor = Theme.card
        c.textLabel?.textColor = Theme.text
        c.detailTextLabel?.textColor = Theme.sub
        c.selectionStyle = .none
        let bg = UIView(); bg.backgroundColor = Theme.cardHi; c.selectedBackgroundView = bg
        c.tintColor = Theme.accent
        return c
    }
    func header(_ s: String) -> UIView {
        let v = UIView(); let l = UILabel()
        l.text = "   " + s.uppercased(); l.font = .systemFont(ofSize: 12, weight: .semibold); l.textColor = Theme.sub
        l.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(l)
        NSLayoutConstraint.activate([l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 4),
                                     l.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -4)])
        return v
    }
    func toast(_ m: String) {
        let a = UIAlertController(title: nil, message: m, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "好", style: .default)); present(a, animated: true)
    }
}

// MARK: - 图1：设置页

final class SettingsVC: DarkTableVC {
    struct Row { let icon: String; let title: String; let detail: String; let action: Int }
    var sections: [(String, [Row])] = []
    override func viewDidLoad() {
        super.viewDidLoad(); title = "设置"
        navigationController?.navigationBar.prefersLargeTitles = true
    }
    override func viewWillAppear(_ a: Bool) { super.viewWillAppear(a); build(); tableView.reloadData() }
    func build() {
        AppEngine.shared.ensureRuntime()
        let js = AppEngine.shared.sources.filter { !$0.group.hasPrefix("示例") }.count
        sections = [
            ("通用", [Row(icon: "circle.lefthalf.filled", title: "外观与显示", detail: "黑暗", action: 0)]),
            ("浏览", [Row(icon: "house", title: "首页内容", detail: "4k影视", action: 0),
                      Row(icon: "film", title: "TMDB 服务", detail: "RB95", action: 0)]),
            ("内容源", [Row(icon: "plus.circle.fill", title: "导入内容源", detail: "链接／文件", action: 1),
                        Row(icon: "doc.text", title: "JSON 网页源", detail: "0个", action: 0),
                        Row(icon: "chevron.left.forwardslash.chevron.right", title: "JS 内容源", detail: "\(js)个", action: 2),
                        Row(icon: "play.rectangle", title: "VOD 内容源", detail: "0个", action: 0),
                        Row(icon: "antenna.radiowaves.left.and.right", title: "M3U 直播源", detail: "0个", action: 0)]),
            ("播放器", [Row(icon: "play.circle", title: "播放设置", detail: "AVPlayer", action: 0),
                        Row(icon: "hand.draw", title: "手势操作", detail: "", action: 0)]),
        ]
    }
    override func numberOfSections(in t: UITableView) -> Int { sections.count }
    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { sections[s].1.count }
    override func tableView(_ t: UITableView, viewForHeaderInSection s: Int) -> UIView? { header(sections[s].0) }
    override func tableView(_ t: UITableView, heightForHeaderInSection s: Int) -> CGFloat { 34 }
    override func tableView(_ t: UITableView, cellForRowAt i: IndexPath) -> UITableViewCell {
        let c = cell("set"); let r = sections[i.section].1[i.row]
        c.textLabel?.text = r.title; c.textLabel?.font = .systemFont(ofSize: 15)
        c.detailTextLabel?.text = r.detail
        c.imageView?.image = UIImage(systemName: r.icon)?.withTintColor(Theme.sub, renderingMode: .alwaysOriginal)
        c.accessoryType = .disclosureIndicator
        return c
    }
    override func tableView(_ t: UITableView, didSelectRowAt i: IndexPath) {
        switch sections[i.section].1[i.row].action {
        case 1: navigationController?.pushViewController(ImportVC(style: .insetGrouped), animated: true)
        case 2: navigationController?.pushViewController(SourcesVC(style: .insetGrouped), animated: true)
        default: break
        }
    }
}

// MARK: - 图2：导入内容源

final class ImportVC: DarkTableVC, UITextFieldDelegate {
    var mode = 0; var urlText = ""; var nameText = ""; var autoType = true
    override func viewDidLoad() {
        super.viewDidLoad(); title = "导入内容源"
        tableView.keyboardDismissMode = .onDrag
        let foot = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 92))
        let btn = UIButton(type: .system)
        btn.setTitle("导入链接", for: .normal); btn.titleLabel?.font = .boldSystemFont(ofSize: 16)
        btn.setTitleColor(.white, for: .normal); btn.backgroundColor = Theme.accent
        btn.layer.cornerRadius = 12
        btn.frame = CGRect(x: 20, y: 24, width: view.bounds.width - 40, height: 50)
        btn.addTarget(self, action: #selector(doImport), for: .touchUpInside)
        foot.addSubview(btn); tableView.tableFooterView = foot
    }
    override func numberOfSections(in t: UITableView) -> Int { 3 }
    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { s == 0 ? 1 : (s == 1 ? 2 : 3) }
    override func tableView(_ t: UITableView, titleForHeaderInSection s: Int) -> String? { s == 1 ? "类型" : nil }
    override func tableView(_ t: UITableView, cellForRowAt i: IndexPath) -> UITableViewCell {
        let c = cell("imp")
        c.contentView.subviews.filter { $0.tag >= 100 }.forEach { $0.removeFromSuperview() }
        c.textLabel?.text = nil; c.detailTextLabel?.text = nil; c.imageView?.image = nil; c.accessoryType = .none
        if i.section == 0 {
            let seg = UISegmentedControl(items: ["链接", "本地文件"])
            seg.selectedSegmentIndex = mode; seg.backgroundColor = Theme.cardHi
            seg.selectedSegmentTintColor = Theme.accent; seg.tag = 100
            seg.frame = CGRect(x: 14, y: 6, width: view.bounds.width - 60, height: 32)
            seg.addTarget(self, action: #selector(segChanged(_:)), for: .valueChanged)
            c.contentView.addSubview(seg)
        } else if i.section == 1 {
            c.textLabel?.text = i.row == 0 ? "自动识别" : "手动选择类型"
            c.imageView?.image = UIImage(systemName: i.row == 0 ? "wand.and.stars" : "hand.tap")
            c.accessoryType = (autoType == (i.row == 0)) ? .checkmark : .none
        } else {
            let tf = UITextField(frame: CGRect(x: 16, y: 4, width: view.bounds.width - 64, height: 36))
            tf.delegate = self; tf.textColor = .white; tf.tag = 200 + i.row
            tf.attributedPlaceholder = NSAttributedString(
                string: ["粘贴内容源链接", "自定义名称（可选）", "图标 URL（可选）"][i.row],
                attributes: [.foregroundColor: Theme.sub])
            tf.autocapitalizationType = .none; tf.autocorrectionType = .no
            tf.keyboardType = i.row == 0 ? .URL : .default
            tf.addTarget(self, action: #selector(fieldChanged(_:)), for: .editingChanged)
            if i.row == 0 { tf.text = urlText } else if i.row == 1 { tf.text = nameText }
            c.contentView.addSubview(tf)
        }
        return c
    }
    override func tableView(_ t: UITableView, didSelectRowAt i: IndexPath) {
        if i.section == 1 { autoType = (i.row == 0); t.reloadSections([1], with: .none) }
    }
    @objc func segChanged(_ s: UISegmentedControl) { mode = s.selectedSegmentIndex }
    @objc func fieldChanged(_ tf: UITextField) {
        if tf.tag == 200 { urlText = tf.text ?? "" } else if tf.tag == 201 { nameText = tf.text ?? "" }
    }
    @objc func doImport() {
        guard let u = URL(string: urlText.trimmingCharacters(in: .whitespaces)),
              u.scheme?.hasPrefix("http") == true else { toast("请输入有效的 http(s) 内容源链接"); return }
        let nm = nameText.isEmpty ? u.lastPathComponent : nameText
        AppEngine.shared.sources.append(ModuleItem(id: nm, title: nm, jsURL: u, isLocal: false, group: "JS 内容源"))
        toast("已导入：\(nm)")
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - 图3：内容源列表

final class SourcesVC: DarkTableVC, UISearchResultsUpdating {
    var filtered: [ModuleItem] = []
    let search = UISearchController(searchResultsController: nil)
    override func viewDidLoad() {
        super.viewDidLoad(); title = "内容源"
        AppEngine.shared.ensureRuntime()
        search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "查找内容源"; search.searchBar.tintColor = Theme.accent
        search.searchBar.searchTextField.textColor = .white
        navigationItem.searchController = search; navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(add))
        filtered = AppEngine.shared.sources
    }
    override func viewWillAppear(_ a: Bool) { super.viewWillAppear(a); filtered = AppEngine.shared.sources; tableView.reloadData() }
    @objc func add() { navigationController?.pushViewController(ImportVC(style: .insetGrouped), animated: true) }
    func updateSearchResults(for sc: UISearchController) {
        let q = (sc.searchBar.text ?? "").lowercased()
        filtered = q.isEmpty ? AppEngine.shared.sources : AppEngine.shared.sources.filter { $0.title.lowercased().contains(q) }
        tableView.reloadData()
    }
    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { max(1, filtered.count) }
    override func tableView(_ t: UITableView, cellForRowAt i: IndexPath) -> UITableViewCell {
        let c = cell("src")
        if filtered.isEmpty { c.textLabel?.text = "无匹配内容源"; return c }
        let it = filtered[i.row]
        c.textLabel?.text = it.title; c.textLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        c.detailTextLabel?.text = it.group
        c.imageView?.image = avatarImage(it.id)
        c.accessoryType = .disclosureIndicator
        return c
    }
    override func tableView(_ t: UITableView, didSelectRowAt i: IndexPath) {
        guard !filtered.isEmpty else { return }
        let it = filtered[i.row]
        if it.jsURL.scheme == "webox" { toast("「\(it.title)」是示例条目\n请在「导入内容源」粘贴该模块的真实 .js 直链"); return }
        AppEngine.shared.loadJS(it) { meta in
            var item = it
            if let d = meta.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                if let mods = o["modules"] as? [[String: Any]] {
                    for x in mods { if let fn = x["functionName"] as? String {
                        if (x["type"] as? String) == "stream" { item.fnPlay = fn } else { item.fnList = fn }
                    } }
                }
                if let sr = o["search"] as? [String: Any], let fn = sr["functionName"] as? String { item.fnSearch = fn }
            }
            let vc = ItemsVC(style: .insetGrouped); vc.module = item
            self.navigationController?.pushViewController(vc, animated: true)
        }
    }
}

// MARK: - 片源列表 + 播放

final class ItemsVC: DarkTableVC {
    var module: ModuleItem!; var items: [[String: Any]] = []; var status = "加载中…"
    override func viewDidLoad() {
        super.viewDidLoad(); title = module.title
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .search, target: self, action: #selector(doSearch))
        Task { await reload(arg: [:]) }
    }
    @objc func doSearch() {
        let a = UIAlertController(title: "搜索", message: nil, preferredStyle: .alert)
        a.addTextField { $0.placeholder = "关键词" }
        a.addAction(UIAlertAction(title: "搜索", style: .default) { _ in
            let q = a.textFields?.first?.text ?? ""
            Task { await self.reload(arg: ["keyword": q, "query": q], fn: self.module.fnSearch) }
        })
        a.addAction(UIAlertAction(title: "取消", style: .cancel)); present(a, animated: true)
    }
    func reload(arg: [String: Any], fn: String? = nil) async {
        status = "加载中…"; tableView.reloadData()
        items = await AppEngine.shared.call(fn ?? module.fnList, arg: arg)
        status = items.isEmpty ? "无结果（模块可能用别的函数名）" : "共 \(items.count) 条 · 点击播放"
        tableView.reloadData()
    }
    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { max(1, items.count) }
    override func tableView(_ t: UITableView, titleForHeaderInSection s: Int) -> String? { status }
    override func tableView(_ t: UITableView, cellForRowAt i: IndexPath) -> UITableViewCell {
        let c = cell("it")
        if items.isEmpty { c.textLabel?.text = status; c.textLabel?.numberOfLines = 0; return c }
        let it = items[i.row]
        c.textLabel?.text = (it["title"] as? String) ?? (it["name"] as? String) ?? (it["vod_name"] as? String) ?? "(无标题)"
        c.textLabel?.font = .systemFont(ofSize: 15, weight: .medium); c.textLabel?.numberOfLines = 2
        c.detailTextLabel?.text = (it["description"] as? String) ?? (it["subtitle"] as? String) ?? ""
        c.accessoryType = .disclosureIndicator
        return c
    }
    override func tableView(_ t: UITableView, didSelectRowAt i: IndexPath) {
        t.deselectRow(at: i, animated: true); guard !items.isEmpty else { return }
        Task { await play(items[i.row]) }
    }
    func play(_ it: [String: Any]) async {
        if let d = it["videoUrl"] as? String, d.hasPrefix("http") { presentPlayer(d); return }
        let link = (it["link"] as? String) ?? (it["id"] as? String) ?? (it["vod_id"] as? String) ?? ""
        let res = await AppEngine.shared.call(module.fnPlay, arg: ["link": link])
        if let u = res.compactMap({ $0["url"] as? String }).first(where: { $0.hasPrefix("http") }) { presentPlayer(u) }
        else { toast("没拿到播放直链（模块可能需要特殊参数）") }
    }
    func presentPlayer(_ u: String) { WeBoxPlayerViewController.present(url: u, from: self) }
}

// MARK: - 入口：落地页 = 设置（对齐图1）

final class AppDelegate: NSObject, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let nav = UINavigationController(rootViewController: SettingsVC(style: .insetGrouped))
        nav.navigationBar.prefersLargeTitles = true; nav.navigationBar.tintColor = Theme.accent
        let ap = UINavigationBarAppearance(); ap.configureWithOpaqueBackground()
        ap.backgroundColor = Theme.bg
        ap.titleTextAttributes = [.foregroundColor: UIColor.white]
        ap.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        nav.navigationBar.standardAppearance = ap; nav.navigationBar.scrollEdgeAppearance = ap
        window?.rootViewController = nav; window?.makeKeyAndVisible()
        return true
    }
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if let nav = window?.rootViewController as? UINavigationController {
            let imp = ImportVC(style: .insetGrouped)
            if url.isFileURL { imp.urlText = url.absoluteString }
            else if let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
                    let q = c.queryItems?.first(where: { $0.name == "url" })?.value { imp.urlText = q }
            nav.pushViewController(imp, animated: true); return true
        }
        return false
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
