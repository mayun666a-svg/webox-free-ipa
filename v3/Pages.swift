import UIKit
import AVKit

@MainActor class ScrollPage:UIViewController {
    let scroll=UIScrollView();let content=WB.stack();let heading=WB.label("",26,true)
    override func viewDidLoad(){super.viewDidLoad();view.backgroundColor=WB.bg;overrideUserInterfaceStyle = .dark;scroll.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(scroll);content.translatesAutoresizingMaskIntoConstraints=false;scroll.addSubview(content);scroll.contentInset.bottom=110
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:view.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:view.trailingAnchor),scroll.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor),scroll.bottomAnchor.constraint(equalTo:view.bottomAnchor),content.leadingAnchor.constraint(equalTo:scroll.contentLayoutGuide.leadingAnchor),content.trailingAnchor.constraint(equalTo:scroll.contentLayoutGuide.trailingAnchor),content.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor),content.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor),content.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor)])
        let top=UIView();heading.translatesAutoresizingMaskIntoConstraints=false;top.addSubview(heading);NSLayoutConstraint.activate([top.heightAnchor.constraint(equalToConstant:70),heading.leadingAnchor.constraint(equalTo:top.leadingAnchor,constant:20),heading.centerYAnchor.constraint(equalTo:top.centerYAnchor)]);content.addArrangedSubview(top)
    }
    func alert(_ title:String,_ message:String){let a=UIAlertController(title:title,message:message,preferredStyle:.alert);a.addAction(UIAlertAction(title:"好",style:.default));present(a,animated:true)}
}

@MainActor final class SettingsPage:ScrollPage {
    var select:((Source)->Void)?
    override func viewDidLoad(){super.viewDidLoad();heading.text="设置";rebuild();NotificationCenter.default.addObserver(forName:Notification.Name("libraryChanged"),object:nil,queue:.main){[weak self]_ in self?.rebuild()}}
    func rebuild(){content.arrangedSubviews.dropFirst().forEach{$0.removeFromSuperview()}
        func row(_ icon:String,_ title:String,_ value:String="",_ action:@escaping()->Void)->UIView {SettingRow(icon,title,value,action:action)}
        let lib=Library.shared
        content.addArrangedSubview(section("通用",rows:[row("square.on.circle","外观与显示",UserDefaults.standard.string(forKey:"appearanceTitle") ?? "黑暗"){[weak self] in self?.appearance()}]))
        content.addArrangedSubview(section("浏览",rows:[row("house","首页内容",lib.source(lib.selected)?.title ?? "TMDB"){[weak self] in self?.present(SourceSheet(onSelect:{s in self?.select?(s)}),animated:true)},row("square.grid.2x2","TMDB 服务"){[weak self] in self?.tmdbSettings()}]))
        content.addArrangedSubview(section("内容源",rows:[row("plus","导入内容源","链接 / 文件"){[weak self] in self?.present(ImportSheet(),animated:true)},row("curlybraces","JSON 网页源","\(lib.count("json")) 个"){[weak self] in self?.manage("json")},row("chevron.left.forwardslash.chevron.right","JS 内容源","\(lib.count("js")) 个"){[weak self] in self?.manage("js")},row("square.3.layers.3d","VOD 内容源","\(lib.count("vod")) 个"){[weak self] in self?.manage("vod")},row("tv","M3U 直播源","\(lib.count("m3u")) 个"){[weak self] in self?.manage("m3u")}]))
        content.addArrangedSubview(section("播放器",rows:[row("play.fill","播放设置","AVPlayer"){[weak self] in self?.playback()},row("hand.draw","手势操作"){[weak self] in self?.alert("手势操作","使用 iOS 播放器控制亮度、音量、进度和画面方向。")},row("internaldrive","视频缓冲","系统管理"){[weak self] in self?.alert("视频缓冲","当前使用 AVPlayer 的自动缓冲管理。Android 的 ExoPlayer/MPV 不是 iOS 播放引擎。") }]))
        content.addArrangedSubview(section("数据",rows:[row("internaldrive","接口缓存","系统管理"){URLCache.shared.removeAllCachedResponses()},row("photo","图片缓存","系统管理"){URLCache.shared.removeAllCachedResponses()},row("folder","备份与恢复"){[weak self] in self?.backup()}]))
        content.addArrangedSubview(section("关于",rows:[row("paperplane","交流频道","@ddgksf2021"){UIApplication.shared.open(URL(string:"https://t.me/ddgksf2021")!)},row("info.circle","WeBox","0.1.79 · iOS 移植"){[weak self] in self?.alert("WeBox","按 Android 0.1.79 安装包重建界面与内容源流程。当前版本是 iOS 移植构建。")},row("doc.text","诊断日志"){[weak self] in self?.diagnostics()},row("chevron.left.forwardslash.chevron.right","开源许可"){[weak self] in self?.alert("开源许可","JavaScript runtime 来自提供的 WeBox APK。原包包含相应第三方许可文件；iOS 播放使用系统 AVPlayer。") }]))
        let footer=WB.label("WeBox 0.1.79 · iOS migration v3",10,false,WB.secondary);footer.textAlignment = .center;footer.heightAnchor.constraint(equalToConstant:70).isActive=true;content.addArrangedSubview(footer)
    }
    func manage(_ kind:String){present(SourceSheet(manage:true,kind:kind,onSelect:{[weak self]s in self?.select?(s)}),animated:true)}
    func appearance(){let a=UIAlertController(title:"外观模式",message:nil,preferredStyle:.actionSheet);for (title,style) in [("黑暗",UIUserInterfaceStyle.dark),("明亮",.light),("跟随系统",.unspecified)] {a.addAction(UIAlertAction(title:title,style:.default){[weak self]_ in UserDefaults.standard.set(title,forKey:"appearanceTitle");self?.view.window?.overrideUserInterfaceStyle=style;self?.rebuild()})};a.addAction(UIAlertAction(title:"取消",style:.cancel));a.popoverPresentationController?.sourceView=view;present(a,animated:true)}
    func tmdbSettings(){let a=UIAlertController(title:"TMDB 服务",message:"配置 API 服务与自己的 API Key",preferredStyle:.alert);a.addTextField{$0.placeholder="https://tmdb.quswer.com/";$0.text=UserDefaults.standard.string(forKey:"tmdbBase") ?? "https://tmdb.quswer.com/";$0.autocapitalizationType = .none};a.addTextField{$0.placeholder="TMDB API Key（可选）";$0.isSecureTextEntry=true;$0.text=UserDefaults.standard.string(forKey:"tmdbKey")};a.addAction(UIAlertAction(title:"保存",style:.default){_ in UserDefaults.standard.set(a.textFields?[0].text,forKey:"tmdbBase");UserDefaults.standard.set(a.textFields?[1].text,forKey:"tmdbKey")});a.addAction(UIAlertAction(title:"取消",style:.cancel));present(a,animated:true)}
    func playback(){let a=UIAlertController(title:"播放设置",message:"iOS 播放引擎：AVPlayer",preferredStyle:.actionSheet);for r in [0.75,1,1.25,1.5,2] {a.addAction(UIAlertAction(title:"默认速度 \(r)×",style:.default){_ in UserDefaults.standard.set(r,forKey:"playbackRate")})};a.addAction(UIAlertAction(title:"取消",style:.cancel));a.popoverPresentationController?.sourceView=view;present(a,animated:true)}
    func backup(){let u=Library.shared.folder.appendingPathComponent("library.json");let a=UIActivityViewController(activityItems:[u],applicationActivities:nil);a.popoverPresentationController?.sourceView=view;present(a,animated:true)}
    func diagnostics(){let text="WeBox iOS v3\n内容源: \(Library.shared.sources.count)\n当前: \(Library.shared.selected)\n播放器: AVPlayer\n系统: \(UIDevice.current.systemVersion)";alert("诊断日志",text)}
}

@MainActor final class BrowsePage:ScrollPage {
    var session:ModuleSession?;var source:Source?;var items:[[String:Any]]=[];var menus:[FavoriteMenu]=[];let grid=WB.stack(.vertical,12);var titleButton:UIButton!;var settingsButton:UIButton!;var query=WB.field("搜索")
    override func viewDidLoad(){super.viewDidLoad();heading.text="发现";let top=WB.stack(.vertical,10);top.isLayoutMarginsRelativeArrangement=true;top.layoutMargins=UIEdgeInsets(top:2,left:20,bottom:12,right:20)
        let sourceRow=WB.stack(.horizontal,10);sourceRow.alignment = .center
        titleButton=UIButton(type:.system);titleButton.setTitle("TMDB  ﹀",for:.normal);titleButton.titleLabel?.font = .systemFont(ofSize:14,weight:.semibold);titleButton.setTitleColor(WB.text,for:.normal);titleButton.backgroundColor=UIColor.white.withAlphaComponent(0.055);titleButton.layer.cornerRadius=18;titleButton.contentEdgeInsets=UIEdgeInsets(top:0,left:14,bottom:0,right:14);titleButton.heightAnchor.constraint(equalToConstant:36).isActive=true;titleButton.widthAnchor.constraint(lessThanOrEqualToConstant:220).isActive=true;titleButton.setContentHuggingPriority(.required,for:.horizontal);titleButton.addAction(UIAction{[weak self] _ in self?.present(SourceSheet(onSelect:{s in self?.load(s)}),animated:true)},for:.touchUpInside)
        sourceRow.addArrangedSubview(titleButton);sourceRow.addArrangedSubview(UIView())
        settingsButton=UIButton(type:.system);settingsButton.setImage(WB.image("gearshape"),for:.normal);settingsButton.tintColor=WB.secondary;settingsButton.widthAnchor.constraint(equalToConstant:36).isActive=true;settingsButton.heightAnchor.constraint(equalToConstant:36).isActive=true;settingsButton.isHidden=true;settingsButton.addAction(UIAction{[weak self] _ in self?.openSettings()},for:.touchUpInside);sourceRow.addArrangedSubview(settingsButton);top.addArrangedSubview(sourceRow)
        query.returnKeyType = .search;query.addTarget(self,action:#selector(searchNow),for:.editingDidEndOnExit);top.addArrangedSubview(query);content.addArrangedSubview(top);grid.isLayoutMarginsRelativeArrangement=true;grid.layoutMargins=UIEdgeInsets(top:8,left:20,bottom:0,right:20);content.addArrangedSubview(grid);load(Library.shared.source(Library.shared.selected) ?? Library.shared.sources[0])}
    @objc func searchNow(){query.resignFirstResponder();guard let s=source else{return};Task {await fetch(s,query:query.text ?? "")}}
    func load(_ s:Source){loadViewIfNeeded();source=s;Library.shared.selected=s.id;if session?.source.id != s.id{session=nil};settingsButton?.isHidden=true;titleButton.setTitle(s.title+"  ﹀",for:.normal);heading.text="发现";Task {await fetch(s)}}
    func openSettings(){guard let session=session else{return};let sheet=ModuleSettingsSheet(session:session){[weak self] in guard let self=self else{return};Task{await self.fetch(session.source)}};present(sheet,animated:true)}
    func message(_ text:String){grid.arrangedSubviews.forEach{$0.removeFromSuperview()};let l=WB.label(text,14,false,WB.secondary);l.numberOfLines=0;l.textAlignment = .center;grid.addArrangedSubview(l)}
    func fetch(_ s:Source,query:String?=nil) async {
        message("加载中…")
        do {
            if s.kind=="library" {try await tmdb(query);return}
            if s.kind=="m3u" {let t=try Library.shared.code(s);var name="";items=[];for line in t.components(separatedBy:.newlines){if line.hasPrefix("#EXTINF"){name=String(line.split(separator:",",maxSplits:1).last ?? "直播")}else if line.hasPrefix("http"){items.append(["title":name,"videoUrl":line])}};render(items);return}
            guard ["js","podcast","radio"].contains(s.kind) else {message("已保存的 \(s.kind.uppercased()) 内容源。此版本尚未实现该格式的浏览解析。");return}
            if session?.source.id != s.id {session=try ModuleSession(s)}
            settingsButton.isHidden = !(session?.hasGlobalFields ?? false)
            items=try await session!.list(query);render(items)
        }catch{
            let text=error.localizedDescription
            if text.contains("API 地址") || text.contains("模块设置") {
                settingsButton.isHidden = !(session?.hasGlobalFields ?? false)
                let alert=UIAlertController(title:"这个源需要模块设置",message:text,preferredStyle:.alert)
                alert.addAction(UIAlertAction(title:"去设置",style:.default){[weak self]_ in self?.openSettings()})
                alert.addAction(UIAlertAction(title:"取消",style:.cancel));present(alert,animated:true)
            } else { message(text) }
        }
    }
    func tmdb(_ q:String?) async throws {
        let base=UserDefaults.standard.string(forKey:"tmdbBase") ?? "https://tmdb.quswer.com/"
        let key=UserDefaults.standard.string(forKey:"tmdbKey") ?? ""
        guard !key.isEmpty || !base.contains("api.themoviedb.org") else {message("发现喜欢的影视，留住想看的故事。\n\n在设置中配置 TMDB 服务，或点击上方「TMDB ﹀」切换到已导入的内容源。");return}
        var c=URLComponents(string:base.trimmingCharacters(in:CharacterSet(charactersIn:"/"))+(q==nil ? "/trending/all/week":"/search/multi"))!
        c.queryItems=[URLQueryItem(name:"language",value:"zh-CN")];if !key.isEmpty{c.queryItems?.append(URLQueryItem(name:"api_key",value:key))};if let q=q{c.queryItems?.append(URLQueryItem(name:"query",value:q))}
        let (d,r)=try await URLSession.shared.data(from:c.url!);guard (r as? HTTPURLResponse)?.statusCode==200 else {throw WBError(message:"TMDB 请求失败，请检查服务和 API Key")}
        let o=try JSONSerialization.jsonObject(with:d) as? [String:Any];let results=o?["results"] as? [[String:Any]] ?? []
        items=results.map{v in var x=v;x["title"]=v["title"] ?? v["name"];if let p=v["poster_path"] as? String{x["posterPath"]="https://image.tmdb.org/t/p/w500"+p};return x};render(items)
    }
    func render(_ list:[[String:Any]]){menus=[];grid.arrangedSubviews.forEach{$0.removeFromSuperview()};guard !list.isEmpty else{message("这个内容源没有栏目结果。可以使用上方搜索查找内容。");return}
        for idx in stride(from:0,to:list.count,by:3){let row=WB.stack(.horizontal,10);row.distribution = .fillEqually
            for i in idx..<min(idx+3,list.count){let item=list[i];let tile=UIControl();let box=WB.stack(.vertical,7);box.isUserInteractionEnabled=false;box.translatesAutoresizingMaskIntoConstraints=false;tile.addSubview(box);NSLayoutConstraint.activate([box.leadingAnchor.constraint(equalTo:tile.leadingAnchor),box.trailingAnchor.constraint(equalTo:tile.trailingAnchor),box.topAnchor.constraint(equalTo:tile.topAnchor),box.bottomAnchor.constraint(equalTo:tile.bottomAnchor)])
                let cover=UIImageView();cover.contentMode = .scaleAspectFill;cover.clipsToBounds=true;cover.layer.cornerRadius=12;cover.backgroundColor=WB.surface;cover.heightAnchor.constraint(equalTo:cover.widthAnchor,multiplier:1.45).isActive=true;box.addArrangedSubview(cover)
                if let p=(item["posterPath"] as? String) ?? (item["poster"] as? String),let u=URL(string:p),u.scheme?.hasPrefix("http")==true {URLSession.shared.dataTask(with:u){d,_,_ in guard let d=d,let im=UIImage(data:d)else{return};DispatchQueue.main.async{cover.image=im}}.resume()}
                let label=WB.label((item["title"] as? String) ?? "未命名",13);label.numberOfLines=2;label.heightAnchor.constraint(equalToConstant:36).isActive=true;box.addArrangedSubview(label)
                tile.addAction(UIAction{[weak self]_ in self?.open(item)},for:.touchUpInside)
                let menu=FavoriteMenu(item:item);menus.append(menu);tile.addInteraction(UIContextMenuInteraction(delegate:menu))
                row.addArrangedSubview(tile)
            };while row.arrangedSubviews.count<3{row.addArrangedSubview(UIView())};grid.addArrangedSubview(row)
        }
    }
    func open(_ item:[String:Any]){
        guard source?.kind != "library" else {alert(item["title"] as? String ?? "TMDB",item["overview"] as? String ?? "影视资料，不提供播放地址。");return}
        Task { @MainActor in
            do {
                if let u=item["videoUrl"] as? String {play(u,item["headers"] as? [String:String] ?? [:]);return}
                if let link=item["link"] as? String,link.hasPrefix("webox:content:"),let session=session {
                    let episodes=try await session.detail(item);let sheet=EpisodeSheet(title:item["title"] as? String ?? "选择分集",items:episodes,onTap:{[weak self]ep in self?.open(ep)});present(sheet,animated:true);return
                }
                guard let session=session else {return};let sources=try await session.play(item);guard let first=sources.first,let url=first["url"] as? String else {throw WBError(message:"未拿到播放地址")};play(url,first["headers"] as? [String:String] ?? [:])
            }catch{alert("播放失败",error.localizedDescription)}
        }
    }
    func play(_ url:String,_ headers:[String:String]){let presenter=presentedViewController ?? self;WeBoxPlayerViewController.present(url:url,headers:headers,from:presenter)}
}

@MainActor final class EpisodeSheet:SheetVC {
    let items:[[String:Any]];let onTap:([String:Any])->Void
    init(title:String,items:[[String:Any]],onTap:@escaping([String:Any])->Void){self.items=items;self.onTap=onTap;super.init(title)}
    required init?(coder:NSCoder){fatalError()}
    override func viewDidLoad(){super.viewDidLoad();for item in items{body.addArrangedSubview(WB.button(item["title"] as? String ?? "播放"){[weak self]in self?.onTap(item)})};if items.isEmpty{body.addArrangedSubview(WB.label("暂无分集",14,false,WB.secondary))}}
}

@MainActor final class RootController:UIViewController {
    let host=UIView();let bar=UIVisualEffectView(effect:UIBlurEffect(style:.systemUltraThinMaterialDark));let selected=UIView();var buttons:[UIButton]=[];var index=0
    lazy var discover=BrowsePage();lazy var settings=SettingsPage();lazy var favorites=ScrollPage()
    override func viewDidLoad(){super.viewDidLoad();view.backgroundColor=WB.bg;overrideUserInterfaceStyle = .dark;host.frame=view.bounds;host.autoresizingMask=[.flexibleWidth,.flexibleHeight];view.addSubview(host);settings.select={[weak self]s in self?.switchTo(0);self?.discover.load(s)}
        favorites.heading.text="收藏";bar.translatesAutoresizingMaskIntoConstraints=false;bar.layer.cornerRadius=27;bar.clipsToBounds=true;bar.layer.borderWidth=0.7;bar.layer.borderColor=UIColor.white.withAlphaComponent(0.16).cgColor;view.addSubview(bar)
        let row=WB.stack(.horizontal);row.distribution = .fillEqually;row.translatesAutoresizingMaskIntoConstraints=false;bar.contentView.addSubview(row);selected.backgroundColor=UIColor.white.withAlphaComponent(0.10);selected.layer.cornerRadius=23;bar.contentView.insertSubview(selected,at:0)
        for (i,symbol) in ["house","heart","gearshape"].enumerated(){let b=UIButton(type:.system);b.setImage(WB.image(symbol),for:.normal);b.tintColor=WB.text;b.accessibilityLabel=["发现","收藏","设置"][i];b.addAction(UIAction{[weak self]_ in self?.switchTo(i)},for:.touchUpInside);row.addArrangedSubview(b);buttons.append(b)}
        NSLayoutConstraint.activate([bar.widthAnchor.constraint(equalToConstant:174),bar.heightAnchor.constraint(equalToConstant:54),bar.centerXAnchor.constraint(equalTo:view.centerXAnchor),bar.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-10),row.leadingAnchor.constraint(equalTo:bar.contentView.leadingAnchor,constant:6),row.trailingAnchor.constraint(equalTo:bar.contentView.trailingAnchor,constant:-6),row.topAnchor.constraint(equalTo:bar.contentView.topAnchor,constant:3),row.bottomAnchor.constraint(equalTo:bar.contentView.bottomAnchor,constant:-3)])
        switchTo(0)
    }
    override func viewDidLayoutSubviews(){super.viewDidLayoutSubviews();selected.frame=CGRect(x:6+CGFloat(index)*54,y:4,width:54,height:46)}
    func switchTo(_ i:Int){index=i;let child=i==0 ? discover:i==1 ? favorites:settings;children.forEach{$0.willMove(toParent:nil);$0.view.removeFromSuperview();$0.removeFromParent()};addChild(child);child.view.frame=host.bounds;child.view.autoresizingMask=[.flexibleWidth,.flexibleHeight];host.addSubview(child.view);child.didMove(toParent:self);if i==1{favorites.heading.text="收藏";favorites.content.arrangedSubviews.dropFirst().forEach{$0.removeFromSuperview()};let saved=Library.shared.favorites
        if saved.isEmpty {let l=WB.label("还没有收藏的内容",14,false,WB.secondary);l.textAlignment = .center;l.heightAnchor.constraint(equalToConstant:150).isActive=true;favorites.content.addArrangedSubview(l)}
        for item in saved {let r=SettingRow("heart",item["title"] as? String ?? "收藏"){[weak self] in let a=UIAlertController(title:item["title"] as? String,message:item["overview"] as? String,preferredStyle:.alert);a.addAction(UIAlertAction(title:"移除收藏",style:.destructive){_ in Library.shared.favorites=Library.shared.favorites.filter{jsonText($0) != jsonText(item)};self?.switchTo(1)});a.addAction(UIAlertAction(title:"关闭",style:.cancel));self?.present(a,animated:true)};favorites.content.addArrangedSubview(r)} };buttons.enumerated().forEach{$0.element.tintColor=$0.offset==i ? WB.accent:WB.text};view.setNeedsLayout()}
}

@MainActor final class FavoriteMenu:NSObject,UIContextMenuInteractionDelegate {
 let item:[String:Any]
 init(item:[String:Any]){self.item=item}
 func contextMenuInteraction(_ interaction:UIContextMenuInteraction,configurationForMenuAtLocation location:CGPoint)->UIContextMenuConfiguration? {
  UIContextMenuConfiguration(identifier:nil,previewProvider:nil){_ in UIMenu(children:[UIAction(title:"收藏",image:WB.image("heart")){_ in var list=Library.shared.favorites;if !list.contains(where:{jsonText($0)==jsonText(self.item)}){list.append(self.item)};Library.shared.favorites=list}])}
 }
}
