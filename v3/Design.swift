import UIKit

enum WB {
    static let bg=UIColor(red:15/255,green:18/255,blue:22/255,alpha:1)
    static let surface=UIColor(red:27/255,green:32/255,blue:39/255,alpha:1)
    static let text=UIColor(red:238/255,green:241/255,blue:246/255,alpha:1)
    static let secondary=UIColor(red:144/255,green:153/255,blue:168/255,alpha:1)
    static let accent=UIColor(red:166/255,green:201/255,blue:255/255,alpha:1)
    static func label(_ text:String,_ size:CGFloat=15,_ bold:Bool=false,_ color:UIColor=WB.text)->UILabel {let l=UILabel();l.text=text;l.font=UIFont.systemFont(ofSize:size,weight:bold ? .semibold:.regular);l.textColor=color;return l}
    static func stack(_ axis:NSLayoutConstraint.Axis = .vertical,_ spacing:CGFloat=0)->UIStackView {let s=UIStackView();s.axis=axis;s.spacing=spacing;return s}
    static func icon(_ name:String,_ size:CGFloat=20,_ color:UIColor=WB.text)->UIImageView {let v=UIImageView(image:UIImage(systemName:name,withConfiguration:UIImage.SymbolConfiguration(pointSize:size,weight:.regular)));v.tintColor=color;v.contentMode = .scaleAspectFit;v.translatesAutoresizingMaskIntoConstraints=false;NSLayoutConstraint.activate([v.widthAnchor.constraint(equalToConstant:size),v.heightAnchor.constraint(equalToConstant:size)]);return v}
    static func field(_ placeholder:String)->UITextField {let f=UITextField();f.placeholder=placeholder;f.attributedPlaceholder=NSAttributedString(string:placeholder,attributes:[.foregroundColor:WB.secondary]);f.textColor=WB.text;f.font = .systemFont(ofSize:14);f.backgroundColor=UIColor.white.withAlphaComponent(0.055);f.layer.cornerRadius=14;f.autocapitalizationType = .none;f.autocorrectionType = .no;let pad=UIView(frame:CGRect(x:0,y:0,width:16,height:1));f.leftView=pad;f.leftViewMode = .always;f.heightAnchor.constraint(equalToConstant:52).isActive=true;return f}
    static func button(_ title:String,_ primary:Bool=false,action:@escaping()->Void)->UIButton {let b=UIButton(type:.system);b.setTitle(title,for:.normal);b.titleLabel?.font = .systemFont(ofSize:14,weight:primary ? .semibold:.regular);b.setTitleColor(primary ? WB.bg:WB.text,for:.normal);b.backgroundColor=primary ? WB.accent:UIColor.white.withAlphaComponent(0.06);b.layer.cornerRadius=24;b.heightAnchor.constraint(equalToConstant:48).isActive=true;b.addAction(UIAction{_ in action()},for:.touchUpInside);return b}
}

class GlassCard:UIView {
    let gradient=CAGradientLayer();let border=CAShapeLayer()
    override init(frame:CGRect) {super.init(frame:frame);layer.cornerRadius=22;clipsToBounds=true
        gradient.colors=[UIColor(red:48/255,green:52/255,blue:60/255,alpha:0.925).cgColor,UIColor(red:38/255,green:43/255,blue:50/255,alpha:0.902).cgColor];gradient.startPoint=CGPoint(x:0,y:0);gradient.endPoint=CGPoint(x:1,y:1);layer.addSublayer(gradient)
        border.fillColor=UIColor.clear.cgColor;border.strokeColor=UIColor.white.withAlphaComponent(0.10).cgColor;border.lineWidth=0.7;layer.addSublayer(border)
    }
    required init?(coder:NSCoder){fatalError()}
    override func layoutSubviews(){super.layoutSubviews();gradient.frame=bounds;border.frame=bounds;border.path=UIBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),cornerRadius:22).cgPath}
}

class SettingRow:UIControl {
    let value:UILabel
    init(_ symbol:String,_ title:String,_ text:String="",action:@escaping()->Void) {
        value=WB.label(text,12,false,WB.secondary);super.init(frame:.zero)
        let stack=WB.stack(.horizontal,14);stack.alignment = .center;stack.isUserInteractionEnabled=false;stack.translatesAutoresizingMaskIntoConstraints=false;addSubview(stack)
        let box=UIView();box.backgroundColor=UIColor(red:63/255,green:140/255,blue:1,alpha:0.094);box.layer.cornerRadius=10;box.translatesAutoresizingMaskIntoConstraints=false;box.widthAnchor.constraint(equalToConstant:32).isActive=true;box.heightAnchor.constraint(equalToConstant:32).isActive=true
        let i=WB.icon(symbol,20);box.addSubview(i);NSLayoutConstraint.activate([i.centerXAnchor.constraint(equalTo:box.centerXAnchor),i.centerYAnchor.constraint(equalTo:box.centerYAnchor)])
        stack.addArrangedSubview(box);let label=WB.label(title);label.setContentCompressionResistancePriority(.defaultLow,for:.horizontal);stack.addArrangedSubview(label)
        value.textAlignment = .right;value.numberOfLines=1;value.widthAnchor.constraint(lessThanOrEqualToConstant:112).isActive=true;value.setContentHuggingPriority(.required,for:.horizontal);stack.addArrangedSubview(value)
        stack.addArrangedSubview(WB.icon("chevron.right",12,WB.secondary.withAlphaComponent(0.5)))
        NSLayoutConstraint.activate([heightAnchor.constraint(greaterThanOrEqualToConstant:60),stack.leadingAnchor.constraint(equalTo:leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:topAnchor,constant:14),stack.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-14)])
        addAction(UIAction{_ in action()},for:.touchUpInside)
    }
    required init?(coder:NSCoder){fatalError()}
    override var isHighlighted:Bool {didSet{alpha=isHighlighted ? 0.65:1}}
}

func section(_ title:String,rows:[UIView])->UIView {
    let all=WB.stack();let header=WB.label(title,12,true,WB.secondary);let h=UIView();h.addSubview(header);header.translatesAutoresizingMaskIntoConstraints=false
    NSLayoutConstraint.activate([h.heightAnchor.constraint(equalToConstant:49),header.leadingAnchor.constraint(equalTo:h.leadingAnchor,constant:24),header.bottomAnchor.constraint(equalTo:h.bottomAnchor,constant:-9)])
    all.addArrangedSubview(h);let inset=UIView();let card=GlassCard();card.translatesAutoresizingMaskIntoConstraints=false;inset.addSubview(card);NSLayoutConstraint.activate([card.leadingAnchor.constraint(equalTo:inset.leadingAnchor,constant:16),card.trailingAnchor.constraint(equalTo:inset.trailingAnchor,constant:-16),card.topAnchor.constraint(equalTo:inset.topAnchor),card.bottomAnchor.constraint(equalTo:inset.bottomAnchor)])
    let group=WB.stack();group.translatesAutoresizingMaskIntoConstraints=false;card.addSubview(group);NSLayoutConstraint.activate([group.leadingAnchor.constraint(equalTo:card.leadingAnchor),group.trailingAnchor.constraint(equalTo:card.trailingAnchor),group.topAnchor.constraint(equalTo:card.topAnchor),group.bottomAnchor.constraint(equalTo:card.bottomAnchor)])
    for (i,r) in rows.enumerated(){if i>0{let line=UIView();let hair=UIView();hair.backgroundColor=UIColor.white.withAlphaComponent(0.07);hair.translatesAutoresizingMaskIntoConstraints=false;line.addSubview(hair);NSLayoutConstraint.activate([line.heightAnchor.constraint(equalToConstant:0.7),hair.leadingAnchor.constraint(equalTo:line.leadingAnchor,constant:62),hair.trailingAnchor.constraint(equalTo:line.trailingAnchor,constant:-16),hair.topAnchor.constraint(equalTo:line.topAnchor),hair.bottomAnchor.constraint(equalTo:line.bottomAnchor)]) ;group.addArrangedSubview(line)};group.addArrangedSubview(r)}
    all.addArrangedSubview(inset);return all
}

class Badge:UIImageView {
    init(_ source:Source,_ size:CGFloat=28){super.init(frame:.zero);contentMode = .scaleAspectFit;layer.cornerRadius=8;clipsToBounds=true;translatesAutoresizingMaskIntoConstraints=false;NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant:size),heightAnchor.constraint(equalToConstant:size)])
        let asset=source.id=="tmdb" ? "source_tmdb":source.kind=="podcast" ? "source_podcasts":source.kind=="radio" ? "source_radio":source.title.lowercased().hasPrefix("one") ? "source_one":source.title.contains("瓜子") ? "source_guazi":""
        if let path=Bundle.main.path(forResource:asset,ofType:"png",inDirectory:"assets"),let img=UIImage(contentsOfFile:path){image=img}else{backgroundColor=WB.surface;let l=WB.label(String(source.title.prefix(1)),15,true);l.frame=CGRect(x:0,y:0,width:size,height:size);l.textAlignment = .center;addSubview(l)}
        if let u=URL(string:source.logo),u.scheme?.hasPrefix("http")==true {URLSession.shared.dataTask(with:u){[weak self] d,_,_ in guard let d=d,let i=UIImage(data:d) else{return};DispatchQueue.main.async{self?.image=i;self?.subviews.forEach{$0.removeFromSuperview()}}}.resume()}
    }
    required init?(coder:NSCoder){fatalError()}
}

class SheetVC:UIViewController {
    let body=WB.stack(.vertical,12);let bottom=WB.stack(.vertical,8);let scroll=UIScrollView();var caption:String
    init(_ title:String){caption=title;super.init(nibName:nil,bundle:nil);modalPresentationStyle = .pageSheet}
    required init?(coder:NSCoder){fatalError()}
    override func viewDidLoad(){super.viewDidLoad();view.backgroundColor=WB.bg;overrideUserInterfaceStyle = .dark
        if let s=sheetPresentationController{s.prefersGrabberVisible=true;s.preferredCornerRadius=28;s.detents=[.custom(identifier:.init("content")){_ in 520},.large()];s.prefersScrollingExpandsWhenScrolledToEdge=true}
        let blur=UIVisualEffectView(effect:UIBlurEffect(style:.systemUltraThinMaterialDark));blur.frame=view.bounds;blur.autoresizingMask=[.flexibleWidth,.flexibleHeight];view.addSubview(blur)
        let header=WB.stack(.horizontal,8);header.alignment = .center;header.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(header);header.addArrangedSubview(WB.label(caption,19,true));let close=UIButton(type:.system);close.setImage(UIImage(systemName:"xmark"),for:.normal);close.tintColor=WB.secondary;close.widthAnchor.constraint(equalToConstant:48).isActive=true;close.heightAnchor.constraint(equalToConstant:48).isActive=true;close.addAction(UIAction{[weak self]_ in self?.dismiss(animated:true)},for:.touchUpInside);header.addArrangedSubview(close)
        scroll.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(scroll);scroll.keyboardDismissMode = .interactive;body.translatesAutoresizingMaskIntoConstraints=false;scroll.addSubview(body);bottom.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(bottom)
        NSLayoutConstraint.activate([header.topAnchor.constraint(equalTo:view.topAnchor,constant:22),header.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:20),header.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-12),scroll.topAnchor.constraint(equalTo:header.bottomAnchor,constant:10),scroll.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:20),scroll.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-20),scroll.bottomAnchor.constraint(equalTo:bottom.topAnchor,constant:-12),body.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor),body.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor),body.leadingAnchor.constraint(equalTo:scroll.contentLayoutGuide.leadingAnchor),body.trailingAnchor.constraint(equalTo:scroll.contentLayoutGuide.trailingAnchor),body.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor),bottom.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:20),bottom.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-20),bottom.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor,constant:-14)])
    }
    func error(_ message:String){let a=UIAlertController(title:"未能完成",message:message,preferredStyle:.alert);a.addAction(UIAlertAction(title:"好",style:.default));present(a,animated:true)}
}
