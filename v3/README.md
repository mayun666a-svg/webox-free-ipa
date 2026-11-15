# WeBox iOS v3：基于原 APK 反编译重建

本构建是原 APK 的 iOS 移植，尚非原 Android App 的完整等价实现。前两版“1:1”“40+6全实现”“内置全部能播”等说法不准确，本文件纠正这些结论。

## 原包核对

完整反编译 APK 的 MainActivity、a42、pl、y80、or1、ur0、rr1、k70、jk0 等实现，精确依据见 `original-ui-spec.md`。原 APK 和反编译源码放在私有检查仓库，未加入公开源码工程。

- 设置卡片：22dp圆角、60dp行高、32dp图标底框、20dp图标、15sp标题、12sp右侧值。
- 原深色配色：#0F1216背景、#EEF1F6文字、#9099A8辅助色、#A6C9FF强调色；卡片渐变#30343C→#262B32。
- 发现/收藏/设置浮动胶囊底栏。设置是其中一个页面，不是整个App的唯一首页。
- 导入、来源选择使用bottom sheet：拖拽柄、关闭键、暗色材质，类型选择展开、名称/图标折叠。
- 来源选择与来源管理是两条不同入口；选择来源会切换发现页。初始只显示真实存在的TMDB/播客/电台，不添加虚构JS源。
- 从原包提取TMDB/播客/电台/ONE/瓜子等图标素材；将原包jk0的自绘路径还原为图标。

## 本次功能修正

- 实际的iOS文件选择器、多选文件读取，http(s)链接下载，2MiB限制。
- sources/widgets/vods合集识别，最多100项；JS需实际加载并检查模块元数据；保存到Documents/Sources/library.json和脚本文件。
- 保存来源、当前来源、收藏。管理入口可移除导入来源。
- JSContext 每个模块单独实例化，避免WeBox.define多次注册冲突。
- JSON bridge允许标量、字符串、bool返回；原版本错误地仅接受数组/对象。
- 异步请求resolver使用独立UUID，避免并发串线。HTTP文本/base64语义、查询参数和JSON正文修正。
- WeBox.define列表读取items，详情读取childItems；WidgetMetadata列表/搜索/流函数通过原版元数据选择。
- TMDB服务按原包默认tmdb.quswer.com（网络可用性另计）；官方API需用户自有Key。

## 必须明确的边界

- 编译和模拟器通过不等于真机上所有第三方源都兼容。真机播放尚未验证。
- JSON网页规则、VOD导入识别可保存，但浏览解析尚未完整移植，会明确提示。
- AES/RSA、DOM验证、memoryHls/mediaProcessor没有完整实现，不能称“全部桥接可用”。遇到依赖此类能力的脚本可能无法运行。
- 外观明亮/跟随系统菜单已提供，但当前自绘调色板主要适配深色；不是完整多主题引擎。
- Android ExoPlayer/MPV未迁入iOS；本包播放使用AVPlayer。
- 本构建不是Rex PRO解锁版，不涉及Rex授权。

## 验证

云端构建手机Mach-O和iOS Simulator两个版本。模拟器实际安装启动，生成设置/导入/来源三屏截图，并运行demo的loadList/search/loadResource；新版增加本地文件导入、存储重载、原生HTTP、并发HTTP断言。以同包 `evidence/selftest.json` 和工作流日志为准。

运行截图是实际Simulator输出，不是HTML概念图，不使用二进制字符串存在性充当UI完成证明。

安装：IPA为ad-hoc构建，需要使用适配设备的重签安装工具及证书。最低iOS17。保留旧包用于回退；不要把本构建当成完整原版功能复刻。
