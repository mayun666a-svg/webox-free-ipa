import UIKit
@MainActor final class AppDelegate:NSObject,UIApplicationDelegate {
    var window:UIWindow?
    func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?) ->Bool {
        window=UIWindow(frame:UIScreen.main.bounds);let root=RootController();window?.rootViewController=root;window?.makeKeyAndVisible()
        let args=ProcessInfo.processInfo.arguments
        if args.contains("--settings") || args.contains("--import") || args.contains("--sources") {root.switchTo(2)}
        DispatchQueue.main.asyncAfter(deadline:.now()+0.8){if args.contains("--import"){root.settings.present(ImportSheet(),animated:false)}else if args.contains("--sources"){root.settings.present(SourceSheet(),animated:false)}}
        if args.contains("--self-test") {Task { @MainActor in
            var report:[String:Any]=[:]
            let rt=JSRuntime();rt.loadRuntime()
            if let u=Bundle.main.url(forResource:"demo",withExtension:"js",subdirectory:"modules"),let code=try? String(contentsOf:u){report["metadata"]=jsonValue(rt.loadModule(code));for (fn,p) in [("loadList",["group":"all"]),("search",["keyword":"bunny"]),("loadResource",["link":"demo:bunny"])] {let raw=await rt.invoke(name:fn,argsJSON:jsonText([p]));report[fn]=jsonValue(raw) ?? raw}}
            let source=Source(id:"probe",title:"probe",kind:"js",location:"")
            report["scalarJSON"]=rt.sync.run("{\"method\":\"url.validate\",\"params\":{\"url\":\"https://example.com/\"}}") ?? "nil"
            let dir=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
            try? jsonText(report).write(to:dir.appendingPathComponent("selftest.json"),atomically:true,encoding:.utf8)
            print("WEBOX_SELFTEST",jsonText(report));_ = source
        }}
        return true
    }
    func application(_ application:UIApplication,open url:URL,options:[UIApplication.OpenURLOptionsKey:Any]=[:])->Bool {
        let sheet=ImportSheet();window?.rootViewController?.present(sheet,animated:true);sheet.loadViewIfNeeded()
        if url.isFileURL {sheet.perform([url])}
        else if let c=URLComponents(url:url,resolvingAgainstBaseURL:false),let s=c.queryItems?.first(where:{$0.name=="url"})?.value {sheet.link.text=s;sheet.update()}
        return true
    }
}
UIApplicationMain(CommandLine.argc,CommandLine.unsafeArgv,nil,NSStringFromClass(AppDelegate.self))
