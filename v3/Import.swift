import UIKit
import UniformTypeIdentifiers

@MainActor final class ImportSheet:SheetVC,UIDocumentPickerDelegate {
    let link=WB.field("粘贴内容源链接"),name=WB.field("使用内容源原有名称"),logo=WB.field("留空自动获取网站图标")
    let modes=PillSegment(items:["链接","本地文件"])
    let typeGrid=WB.stack(.vertical,6),custom=WB.stack(.vertical,8)
    let types=[("auto","自动识别"),("json","JSON 网页源"),("js","JS 内容源"),("vod","VOD 接口"),("m3u","M3U 直播源"),("podcast","播客 JS 源"),("radio","电台 JS 源")]
    var kind="auto",busy=false;var customButton:UIButton!;var typeButton:UIButton!;var submit:UIButton!;var fileButton:UIButton!;var status=WB.label("",12,false,WB.secondary)
    init(){super.init("导入内容源")}
    required init?(coder:NSCoder){fatalError()}
    override func viewDidLoad(){super.viewDidLoad();modes.selectedSegmentIndex=0;modes.selectedSegmentTintColor=UIColor.white.withAlphaComponent(0.15);modes.backgroundColor=UIColor.white.withAlphaComponent(0.06);modes.setTitleTextAttributes([.foregroundColor:WB.text,.font:UIFont.systemFont(ofSize:14,weight:.semibold)],for:.normal);modes.heightAnchor.constraint(equalToConstant:48).isActive=true;modes.addAction(UIAction{[weak self]_ in self?.update()},for:.valueChanged);body.addArrangedSubview(modes)
        typeButton=UIButton(type:.system);typeButton.contentHorizontalAlignment = .right;typeButton.setTitle("自动识别  ﹀",for:.normal);typeButton.tintColor=WB.text;typeButton.titleLabel?.font = .systemFont(ofSize:14,weight:.semibold);typeButton.addAction(UIAction{[weak self]_ in self?.typeGrid.isHidden.toggle()},for:.touchUpInside)
        let typeRow=WB.stack(.horizontal);typeRow.alignment = .center;typeRow.addArrangedSubview(WB.label("类型",13,false,WB.secondary));typeRow.addArrangedSubview(typeButton);typeRow.heightAnchor.constraint(equalToConstant:56).isActive=true;body.addArrangedSubview(typeRow)
        for idx in stride(from:0,to:types.count,by:2){let row=WB.stack(.horizontal,8);row.distribution = .fillEqually;for k in idx..<min(idx+2,types.count){let entry=types[k];let b=WB.button(entry.1){[weak self] in self?.kind=entry.0;self?.typeButton.setTitle(entry.1+"  ﹀",for:.normal);self?.typeGrid.isHidden=true};row.addArrangedSubview(b)};if idx==types.count-1{row.addArrangedSubview(UIView())};typeGrid.addArrangedSubview(row)}
        typeGrid.isHidden=true;body.addArrangedSubview(typeGrid);body.addArrangedSubview(link)
        link.keyboardType = .URL;logo.keyboardType = .URL
        fileButton=WB.button("从设备导入  ·  支持多选，自动识别"){[weak self] in self?.pick()};fileButton.isHidden=true;body.addArrangedSubview(fileButton)
        customButton=WB.button("自定义名称与图标  ·  点击展开"){[weak self] in guard let self=self else{return};self.custom.isHidden.toggle();self.customButton.setTitle(self.custom.isHidden ? "自定义名称与图标  ·  点击展开":"收起名称与图标",for:.normal)};customButton.contentHorizontalAlignment = .left;customButton.contentEdgeInsets=UIEdgeInsets(top:0,left:16,bottom:0,right:16);body.addArrangedSubview(customButton)
        custom.addArrangedSubview(WB.label("名称（可选）",12,false,WB.secondary));custom.addArrangedSubview(name);custom.addArrangedSubview(WB.label("图标 URL（可选）",12,false,WB.secondary));custom.addArrangedSubview(logo);custom.isHidden=true;body.addArrangedSubview(custom)
        status.numberOfLines=0;body.addArrangedSubview(status)
        submit=WB.button("导入链接",true){[weak self] in self?.runImport()};bottom.addArrangedSubview(submit)
        link.addAction(UIAction{[weak self]_ in self?.update()},for:.editingChanged);update()
    }
    func update(){let file=modes.selectedSegmentIndex==1;link.isHidden=file;fileButton.isHidden = !file;submit.setTitle(file ? "选择文件":"导入链接",for:.normal);let active=file || !(link.text ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty;submit.isEnabled=active && !busy;submit.alpha=active ? 1:0.5}
    func pick(){let p=UIDocumentPickerViewController(forOpeningContentTypes:[.item],asCopy:false);p.allowsMultipleSelection=true;p.delegate=self;present(p,animated:true)}
    func runImport(){if modes.selectedSegmentIndex==1{pick();return};guard let str=link.text?.trimmingCharacters(in:.whitespacesAndNewlines),let u=URL(string:str),["http","https"].contains(u.scheme ?? "") else {error("请输入完整的 HTTP 或 HTTPS 链接");return};perform([u])}
    func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]){perform(urls)}
    func perform(_ urls:[URL]){guard !busy else{return};busy=true;submit.isEnabled=false;view.endEditing(true)
        Task { @MainActor in var added=0;var errors:[String]=[]
            for (idx,u) in urls.enumerated(){submit.setTitle("正在导入 \(idx+1)/\(urls.count)…",for:.normal);let r=await Library.shared.importURL(u,kind:kind,name:name.text ?? "",logo:logo.text ?? "");added += r.added.count;errors += r.failed}
            status.text=added>0 ? "已导入 \(added) 个内容源。可以继续添加，或关闭后在发现页切换。":"未能导入"
            if !errors.isEmpty{status.text=(status.text ?? "")+"\n\n"+errors.joined(separator:"\n")};busy=false;update()
        }
    }
}

@MainActor final class SourceSheet:SheetVC {
    let search=WB.field("查找内容源");let list=WB.stack();var management=false;var filter:String?;var choose:((Source)->Void)?
    init(manage:Bool=false,kind:String?=nil,onSelect:((Source)->Void)?=nil){self.management=manage;filter=kind;choose=onSelect;super.init(manage ? "管理内容源":"内容源")}
    required init?(coder:NSCoder){fatalError()}
    override func viewDidLoad(){super.viewDidLoad();sheetPresentationController?.detents=[.large()];if Library.shared.sources.count>6 || management {body.addArrangedSubview(search);search.addAction(UIAction{[weak self]_ in self?.rebuild()},for:.editingChanged)};body.addArrangedSubview(list)
        if management{bottom.addArrangedSubview(WB.button("导入内容源",true){[weak self] in self?.present(ImportSheet(),animated:true)})};rebuild();NotificationCenter.default.addObserver(forName:Notification.Name("libraryChanged"),object:nil,queue:.main){[weak self]_ in self?.rebuild()}
    }
    func rebuild(){list.arrangedSubviews.forEach{$0.removeFromSuperview()};let q=(search.text ?? "").lowercased();let kinds=[("library","资料库"),("json","JSON"),("js","JS"),("vod","VOD"),("m3u","M3U")]
        for (kind,title) in kinds {let sources=Library.shared.sources.filter{(filter==nil || $0.kind==filter) && (kind=="library" ? ["library","podcast","radio"].contains($0.kind):$0.kind==kind) && (q.isEmpty || $0.title.lowercased().contains(q))};if sources.isEmpty{continue}
            let label=WB.label(title,11,true,WB.secondary);let pad=UIView();pad.addSubview(label);label.frame=CGRect(x:10,y:12,width:200,height:20);pad.heightAnchor.constraint(equalToConstant:36).isActive=true;list.addArrangedSubview(pad)
            for source in sources {let row=UIControl();let horizontal=WB.stack(.horizontal,14);horizontal.isUserInteractionEnabled=false;horizontal.alignment = .center;horizontal.translatesAutoresizingMaskIntoConstraints=false;row.addSubview(horizontal);horizontal.addArrangedSubview(Badge(source));horizontal.addArrangedSubview(WB.label(source.title,14,Library.shared.selected==source.id));if Library.shared.selected==source.id{horizontal.addArrangedSubview(WB.icon("checkmark",20,WB.accent));row.backgroundColor=WB.accent.withAlphaComponent(0.16);row.layer.cornerRadius=16}
                NSLayoutConstraint.activate([row.heightAnchor.constraint(equalToConstant:48),horizontal.leadingAnchor.constraint(equalTo:row.leadingAnchor,constant:12),horizontal.trailingAnchor.constraint(equalTo:row.trailingAnchor,constant:-12),horizontal.centerYAnchor.constraint(equalTo:row.centerYAnchor)])
                row.addAction(UIAction{[weak self]_ in guard let self=self else{return};if self.management {self.manage(source)}else{Library.shared.selected=source.id;self.dismiss(animated:true){self.choose?(source)}}},for:.touchUpInside);list.addArrangedSubview(row)
            }
        }
        if list.arrangedSubviews.isEmpty {let empty=WB.label("没有匹配的内容源",13,false,WB.secondary);empty.textAlignment = .center;list.addArrangedSubview(empty)}
    }
    func manage(_ s:Source){let a=UIAlertController(title:s.title,message:nil,preferredStyle:.actionSheet);a.addAction(UIAlertAction(title:"在发现页浏览",style:.default){[weak self]_ in Library.shared.selected=s.id;self?.dismiss(animated:true){self?.choose?(s)}});if !s.builtin{a.addAction(UIAlertAction(title:"移除内容源",style:.destructive){_ in Library.shared.remove(s.id)})};a.addAction(UIAlertAction(title:"取消",style:.cancel));a.popoverPresentationController?.sourceView=view;present(a,animated:true)}
}
