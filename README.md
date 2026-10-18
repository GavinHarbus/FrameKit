# FrameKit

非沙盒 macOS 截图工具 MVP。选择正在运行的应用和具体窗口，设置宽高并读回实际结果，截图、预览，再导出指定像素尺寸的 PNG。所有图像在本地处理。

## 运行

要求 macOS 14 或更新版本。打开 `FrameKit.xcodeproj`，选择 **FrameKit → My Mac → Run**。项目使用本机已有的 Apple Development 证书签名；其他开发者需在 Signing & Capabilities 选择自己的团队并同步修改 `project.yml`。已构建的应用可直接在 Finder 双击启动。

1. 点击工具栏的 **系统权限**，请求 **辅助功能** 和 **屏幕录制** 权限。权限状态会自动更新；获得屏幕录制权限后点击 **刷新窗口**。系统要求重新打开时，退出并重新启动。
2. 从左侧应用列表选择应用，再在右侧检查器选择具体窗口。仅列出当前屏幕上可捕获的普通窗口，不包含最小化窗口。
3. 输入窗口外框宽高（**pt**，含标题栏）。可选填写位置；坐标以主屏左上角为原点，向右、向下为正。
4. 在检查器中点击 **调整并截图 / 仅调整**，或点击工具栏的 **截图 / 重拍**。应用会等待布局稳定并显示实际结果。目标应用可能限制最小尺寸或位置；即使请求未完全生效，也会明确显示实际尺寸。
5. 在检查器的 **导出** 中选择原图像素尺寸，或输入宽高（**px**）。支持等比留白、居中裁剪、拉伸；已移除背景设置，等比留白固定为白色。
6. 点击工具栏 **导出** 保存 PNG，应用会校验实际文件的像素尺寸、格式及透明通道；可直接在 Finder 中定位文件。

快捷键：`⌘R` 刷新、`⌘K` 截图、`⌘E` 导出。重拍失败会保留上一次截图并明确提示。切换目标窗口会清除原预览，避免导出错误对象。

界面采用原生 NavigationSplitView、sidebar 列表、统一工具栏和可收起的 inspector。macOS 26 自动使用系统 Liquid Glass 导航与工具栏样式，颜色和明暗外观跟随系统；macOS 14/15 使用相应的原生样式。

应用图标使用提供的 FrameKit logo。原图保存在 `Design/FrameKit-logo-original.png`，适配后的透明边缘图标及生成说明见 [Design/README.md](Design/README.md)。AppIcon 资源已包含 macOS 的全部十个尺寸槽位。

## 界面语言

支持 **English（en）** 和 **简体中文（zh-Hans）**。英文为源语言和回退语言；应用默认按 macOS 的首选语言顺序选择受支持语言。没有匹配语言时使用英文。

若要保持中文系统、仅让 FrameKit 显示英文：前往 **系统设置 → 通用 → 语言与地区 → 应用程序**，添加 FrameKit 并选择 English，然后重新打开应用。应用内不另设语言切换器，也不覆盖系统语言偏好。

- `Resources/Localizable.xcstrings` 管理界面、菜单、帮助、状态和错误；`Resources/InfoPlist.xcstrings` 管理屏幕捕获权限的用途说明。
- 新文案先编写英文，再在 String Catalog 中补充简体中文。SwiftUI 使用本地化文本；运行时文案使用 `String(localized:)`。有条件分支的文案也必须分别本地化。
- FrameKitCore 为静态库，使用 `AppLocalization.bundle` 查找宿主资源；测试目标打包同一份目录以验证实际编译后的翻译。
- 应用名、窗口标题、文件路径保持原样。窗口 ID 和 AX 错误码作为文本插值，避免添加千位分隔符；`pt`、`px`、PNG、sRGB 保持一致。动态变量放在完整句子的占位符内，不拼接翻译片段。新增数量文案时在 String Catalog 中配置 plural variants。
- 修改文案后构建会产生 `.stringsdata`，可运行 `python3 Tools/CheckLocalizations.py` 检查提取到的所有界面文案都有双语翻译。

## 构建与测试

仓库包含生成好的 Xcode 项目；正常使用无需安装 XcodeGen。修改 `project.yml` 后可用 XcodeGen 重新生成。

```sh
xcodebuild -project FrameKit.xcodeproj -scheme FrameKit -configuration Debug -derivedDataPath build build
xcodebuild -project FrameKit.xcodeproj -scheme FrameKit -destination 'platform=macOS' -derivedDataPath build test
```

语言回归检查：

```sh
xcodebuild -project FrameKit.xcodeproj -scheme FrameKit -destination 'platform=macOS' -derivedDataPath build -testLanguage en -testRegion US test
xcodebuild -project FrameKit.xcodeproj -scheme FrameKit -destination 'platform=macOS' -derivedDataPath build -testLanguage zh-Hans -testRegion CN test
python3 Tools/CheckLocalizations.py
```

Debug 应用位于 `build/Build/Products/Debug/FrameKit.app`。Debug 和 Release 统一使用名称 **FrameKit**、Bundle ID `com.framekit.local` 及相同的 Apple Development 证书签名，仅保留调试与优化等编译配置差异。证书签名保持跨构建的应用身份，避免之前 ad-hoc 签名每次改动代码后身份变化。对外分发仍需 Developer ID 签名及公证。

之前仅授权过 **FrameKit Debug** 的用户，首次使用统一版本时需为 **FrameKit** 授权；旧的 FrameKit Debug 记录可在系统设置中移除。

本次同时生成了可直接启动的 Release 应用：`build/Build/Products/Release/FrameKit.app`（Apple Silicon / Intel 通用二进制）。

### 已授权却仍显示未授权

旧的 ad-hoc 构建会让系统设置保留旧签名的授权记录，即使开关已打开，macOS 仍可能拒绝当前构建。迁移到本次证书签名版本时，需要一次性移除系统设置里的旧 FrameKit 记录，再通过 Finder 将实际使用的 FrameKit.app 添加到系统设置并开启权限。此类开发构建的排障信息仅保留在文档中，不在权限弹窗中显示。不要修改系统权限数据库。

应用在前台每秒检查一次权限；点击授权或打开系统设置后，会在后台继续检查两分钟。返回前台立即重新检查，权限撤销也会同步更新。检查过程不反复弹出授权请求。

## 技术边界

- **这不是 Mac App Store 构建**：App Sandbox 关闭。Release 已验证启用 Hardened Runtime，且不含调试授权 entitlement；Debug 使用 Xcode 的本机调试签名行为。正式 Developer ID 签名后需另行验证。没有 Apple Events、内置脚本或第三方依赖。
- 窗口控制通过公开 Accessibility API 完成；捕获通过 ScreenCaptureKit。截图始终按选定的窗口 ID 和进程 ID 解析，不默默切换到前台窗口。
- AX 与截图窗口通过同进程的外框几何、标题进行保守匹配。重叠且无法区分的窗口会拒绝调整，提示先手动移开；可直接截图。未使用私有窗口 ID API。
- 仅支持普通非全屏窗口。目标应用不暴露可写尺寸、无响应或限制最小尺寸时，无法强制覆盖。不会自动退出全屏、恢复最小化或切换 Spaces。
- 捕获不包含光标、窗口阴影；macOS 14.2 起显式排除子窗口。输出为不透明 sRGB PNG，透明圆角和留白固定合成为白色。画面周围的预览阴影只用于界面展示，不会写入导出图片。受系统保护的内容可能无法捕获。
- 窗口逻辑点与截图像素并非同一单位。导出精确像素尺寸并不增加原图细节。每边最多 16384 像素，总计最多 6400 万像素。
- 当前没有配置预设持久化、批量导出、自由裁剪或商店发布配置。

## 验证

自动测试覆盖非法尺寸、超大图防护、多窗口歧义、尺寸读回判断、三种缩放的实际像素、透明图合成、不含 alpha 的 PNG 编码及文件写入校验。

2026-10-18 本机验证：权限修复后 Debug、Release 构建成功，12 项测试全部通过；新增的 4 项回归测试覆盖异步授权、后台检测、撤销、取消监听和避免重复通知。Release 启动与完整签名校验通过，签名要求已从构建哈希变为证书身份。真实跨应用截图链路仍需用户授予当前构建权限后验证。

本地化验证：英文与简体中文环境分别通过全部 17 项测试；校验双语资源完整性、格式占位符、权限用途说明、核心错误、名称保留及英文回退。Release 已实际启动检查英文和中文工具栏与检查器；仅指定日文首选语言时正确回退英文。语言测试使用临时启动参数，不修改用户的持久语言设置。

选择状态回归：侧边栏与窗口选择器先更新视图本地状态，再提交给 AppModel，避免原生 List 更新过程中同步发布 ObservableObject 变更。新增 4 项选择测试（共 21 项）全部通过；复现切换应用导致的 SwiftUI 发布警告后，已在修复版重放连续切换和导出参数编辑，未再出现该警告。

真实跨应用操作需要用户在 macOS 中授权，不能由测试自动授予。首次运行请用 NyxAstra 及另一个普通应用验证：

- 正常尺寸：调整到 1280 × 800 pt，检查读回值，再截取、导出。
- 最小尺寸：请求过小尺寸，确认显示实际值而非假报成功。
- 多窗口：选择非前台文档，确认调整和截图都是所选窗口。
- 失效目标：选择后关闭或最小化窗口，确认报错而非截取其他窗口。
- Retina / 外接屏：比较窗口 pt 与原图 px，导出 2560 × 1600 PNG 并在预览的检查器核对。
- 权限拒绝与撤销：确认有可恢复的提示，重新授权后可刷新继续。

官方 API 参考：[Accessibility](https://developer.apple.com/documentation/applicationservices/axuielement_h)、[ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)、[ImageIO](https://developer.apple.com/documentation/imageio)。
