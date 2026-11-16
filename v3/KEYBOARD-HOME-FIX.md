# build 87：键盘收起与主页左上角

## 用户反馈
- 导入弹层弹起键盘后收不下去，底部「导入链接」被键盘盖住。
- 主页左上角仍不对：TMDB 选择器是一条几乎空白的整宽胶囊。

## 修复
- `SheetVC` 底部操作区增加 `keyboardLayoutGuide` 约束：键盘出现时按钮上移，隐藏时回到安全区；不再被键盘盖住。
- 增加点空白收键盘的手势（不拦截按钮点击），并为三个输入框提供键盘上方「完成」按钮和 Return 收起。
- `ImportSheet` 适配 `UITextFieldDelegate`；自测实际调用 `becomeFirstResponder()` 后 `dismissKeyboard()`，检查 `isFirstResponder` 从 true 变 false。
- 主页「TMDB」选择器改为按内容收窄的胶囊（36pt 高、最大 220pt，内容 hugging），不再拉满整行；与「发现」标题和搜索框重新排布。
- 新增 `--home` 与 `--import-keyboard` 模拟器截图入口，实际生成主页与键盘态截图。

## 验证（run 43768728496）
- 真实模拟器启动，截取 settings / import / import-file / import-keyboard / sources / home 六屏。
- OCR 确认 `import-keyboard` 中「导入链接」文字仍存在（按钮在键盘上方）；`home` 中「发现」「TMDB」「搜索」按顺序出现，选择器实测宽度约屏宽 22%。
- 自测 `keyboardFocus=true`、`keyboardDismissed=true`、`pickerCallbackSaved=true`、`fileImportAdded=1`、`capabilityMetadataImportAdded=1`、`invalidScriptErrors` 包含 fixture-specific-error、并发 HTTP 两个独立响应 200。

## 仍然不能说
- 真机安装/播放未实测；`supjav.webox.js` 原始文件未上传，未验证该具体脚本。
- `.rex` 订阅链接会被解析为 widgets 数组并逐条导入；单个模块依赖 DOM/AES 等未实现能力时可能只能保存、不能完整浏览。
