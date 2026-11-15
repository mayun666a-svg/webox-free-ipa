import UIKit
import UniformTypeIdentifiers
@MainActor final class AppDelegate:NSObject,UIApplicationDelegate {
    var window:UIWindow?
    func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?) ->Bool {
        window=UIWindow(frame:UIScreen.main.bounds);let root=RootController();window?.rootViewController=root;window?.makeKeyAndVisible()
        let args=ProcessInfo.processInfo.arguments
        if args.contains("--settings") || args.contains("--import") || args.contains("--import-file") || args.contains("--sources") {root.switchTo(2)}
        if args.contains("--home") {root.switchTo(0)}
        DispatchQueue.main.asyncAfter(deadline:.now()+0.8){if args.contains("--import") || args.contains("--import-file") || args.contains("--import-keyboard"){let sheet=ImportSheet();root.settings.present(sheet,animated:false);sheet.loadViewIfNeeded();if args.contains("--import-file"){sheet.modes.selectedSegmentIndex=1;sheet.update()}else if args.contains("--import-keyboard"){DispatchQueue.main.asyncAfter(deadline:.now()+0.4){sheet.link.becomeFirstResponder()}}}else if args.contains("--sources"){root.settings.present(SourceSheet(),animated:false)}}
        if args.contains("--self-test") {Task { @MainActor in
            var report:[String:Any]=[:]
            let rt=JSRuntime();rt.loadRuntime()
            if let u=Bundle.main.url(forResource:"demo",withExtension:"js",subdirectory:"modules"),let code=try? String(contentsOf:u){report["metadata"]=jsonValue(rt.loadModule(code));for (fn,p) in [("loadList",["group":"all"]),("search",["keyword":"bunny"]),("loadResource",["link":"demo:bunny"])] {let raw=await rt.invoke(name:fn,argsJSON:jsonText([p]));report[fn]=jsonValue(raw) ?? raw}}
            let source=Source(id:"probe",title:"probe",kind:"js",location:"")
            report["scalarJSON"]=rt.sync.run("{\"method\":\"url.validate\",\"params\":{\"url\":\"https://example.com/\"}}") ?? "nil"
            let dir=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
            try? jsonText(report).write(to:dir.appendingPathComponent("selftest.json"),atomically:true,encoding:.utf8)
            if let demo=Bundle.main.url(forResource:"demo",withExtension:"js",subdirectory:"modules") {
                let imported=await Library.shared.importURL(demo,name:"自测公开示例")
                report["fileImportAdded"]=imported.added.count;report["fileImportFailed"]=imported.failed
                if let added=imported.added.first,let session=try? ModuleSession(added) {report["importedList"]=try? await session.list();Library.shared.remove(added.id)}
                report["libraryReloadCount"]=Library().sources.count
            }
            let fixture=dir.appendingPathComponent("dom-declaration.webox.js")
            let fixtureCode="""
            WeBox.define({api:'1.4',id:'test.dom.metadata',name:'DOM声明导入测试',version:'1.0.0',requires:['dom'],list:async()=>({items:[],nextCursor:null}),detail:async()=>({}),play:async()=>({sources:[]})});
            """
            try? fixtureCode.write(to:fixture,atomically:true,encoding:.utf8)
            let declaration=await Library.shared.importURL(fixture)
            report["capabilityMetadataImportAdded"]=declaration.added.count;report["capabilityMetadataImportErrors"]=declaration.failed
            report["capabilityMetadataWarning"]=Library.shared.lastImportWarning
            for item in declaration.added {Library.shared.remove(item.id)}
            let bad=dir.appendingPathComponent("bad-script.js");try? "WidgetMetadata={id:'broken'};throw new Error('fixture-specific-error');".write(to:bad,atomically:true,encoding:.utf8)
            let rejected=await Library.shared.importURL(bad);report["invalidScriptErrors"]=rejected.failed
            if let demo=Bundle.main.url(forResource:"demo",withExtension:"js",subdirectory:"modules") {
                let ui=ImportSheet();root.present(ui,animated:false);ui.loadViewIfNeeded();ui.documentPicker(UIDocumentPickerViewController(forOpeningContentTypes:[.item],asCopy:true),didPickDocumentsAt:[demo])
                try? await Task.sleep(nanoseconds:1_500_000_000)
                report["pickerCallbackStatus"]=ui.status.text;report["pickerCallbackSaved"]=Library.shared.sources.contains{$0.id != "tmdb" && !$0.builtin && $0.title == "公开示例"}
                for s in Library.shared.sources where !s.builtin {Library.shared.remove(s.id)};ui.dismiss(animated:false)
            }
            let kb=ImportSheet();root.present(kb,animated:false);kb.loadViewIfNeeded();kb.link.becomeFirstResponder();try? await Task.sleep(nanoseconds:400_000_000);report["keyboardFocus"]=kb.link.isFirstResponder;kb.dismissKeyboard();try? await Task.sleep(nanoseconds:300_000_000);report["keyboardDismissed"] = !kb.link.isFirstResponder;kb.dismiss(animated:false)
            let networkCode="""
            async function networkProbe(){var r=await Widget.http.get('http://127.0.0.1:8877/probe.json',{params:{one:'1'}});return [{status:r.statusCode,data:r.data}];}
            async function concurrentProbe(){var r=await Promise.all([Widget.http.get('http://127.0.0.1:8877/a.json'),Widget.http.get('http://127.0.0.1:8877/b.json')]);return r.map(x=>({status:x.statusCode,data:x.data}));}
            """
            rt.ctx.evaluateScript(networkCode)
            report["networkProbe"]=jsonValue(await rt.invoke(name:"networkProbe",argsJSON:"[]"))
            report["concurrentProbe"]=jsonValue(await rt.invoke(name:"concurrentProbe",argsJSON:"[]"))
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
