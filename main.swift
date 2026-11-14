// main.swift — 命令行 swiftc 路线的 @main 等价入口（图形化 Xcode 工程不需要本文件）
// 用法：xcrun -sdk iphoneos swiftc ... WeBoxHost.swift main.swift -o WeBox.app/WeBox
import UIKit
import Foundation

final class AppDelegate: NSObject, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let root = UIViewController()
        root.view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "WeBox iOS Host\n加载 JS 规则层中…"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        root.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: root.view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: root.view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: root.view.leadingAnchor, constant: 24),
        ])
        window?.rootViewController = root
        window?.makeKeyAndVisible()

        Task {
            await weboxBootExample()   // WeBoxHost.swift 末尾：加载 5 个 runtime + demo.js 并实跑 loadList
            await MainActor.run { label.text = "WeBox iOS Host\nJS 规则层已跑通（见控制台 loadList 输出）" }
        }
        return true
    }

    // 支持「文件」App / 浏览器把 .js 模块或 rex://widget 深链丢进来
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if url.isFileURL, let js = try? String(contentsOf: url, encoding: .utf8) {
            let rt = JSRuntime(); rt.loadRuntime()
            print("[WeBox] 导入模块元数据:", rt.loadModule(js))
            return true
        }
        return false
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
