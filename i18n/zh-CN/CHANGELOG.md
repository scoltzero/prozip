# 更新日志

[English](../../CHANGELOG.md) · **简体中文** · [繁體中文](../zh-TW/CHANGELOG.md) · [日本語](../ja/CHANGELOG.md) · [한국어](../ko/CHANGELOG.md) · [Español](../es/CHANGELOG.md) · [Français](../fr/CHANGELOG.md) · [Deutsch](../de/CHANGELOG.md) · [Русский](../ru/CHANGELOG.md)

本项目（**ProZip**）的所有重要变更均记录于此文件中。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，版本号遵循 [语义化版本 (SemVer)](https://semver.org/lang/zh-CN/)。

---

## [0.1.5] - 2026-11-23

### 新增 (Added)
- **应用内一键更新（下载、校验并自动重启）**：
  - 在检查更新弹窗中新增「立即更新」能力，无需跳转浏览器手动下载镜像。
  - 直接在应用内流式下载 GitHub Release 中的 `.zip` 安装包并实时显示下载进度，自动校验 `SHA256SUMS.txt` 哈希与 `CFBundleIdentifier`，通过系统 `ditto` 解压并原子替换当前 `ProZip.app`（失败自动回滚备份，目录无写权限时拉起系统授权弹窗）后自动重启新版。

### 修复与优化 (Fixed & Changed)
- **菜单栏黑白模板图标与弹窗贴边间距修复**：
  - 将状态栏图标改为基于品牌矢量路径绘制的 macOS 黑白模板图标（`isTemplate = true`），去除绿色底色，仅保留主体 **P** 与 33% 透明度折影，自动适配浅色/深色模式及 Retina 分辨率。
  - 收紧菜单栏文件盒面板顶部内边距并锚定菜单栏下沿，消除弹窗与菜单栏之间的多余空隙，同步对齐设置页外观预览。
- **全格式与分卷 RAR 实时解压进度**：修复分卷 RAR 及其他归档格式解压时进度条更新不及时的问题，实现全格式实时流式进度上报。

---

## [0.1.4] - 2026-11-21

### 新增 (Added)
- **程序坞图标显示/隐藏设置**：在「设置 → 通用 → 启动」中新增 **「在程序坞中显示」** 开关，支持无需重启实时切换程序坞图标显示与隐藏（动态调整 `NSApplication.ActivationPolicy` 并保持当前活跃窗口焦点）；同时在菜单栏文件盒右键菜单中补充 **「设置…」** 快捷入口，同步提供简中、繁中、英文三语界面文案。
- **任务队列精细清理与独立可缩放创建窗口**：
  - 归档任务队列窗口（`ArchiveProgressWindowView`）新增单条任务移除按钮、一键「清理已完成」（包含失败项）与「全部清空」能力。
  - 创建压缩包配置弹窗（`ArchiveCreationDialogView`）升级为独立可自由调整尺寸的窗口并自动记忆窗口大小；概览卡片中的辅助文件过滤与文件名兼容行支持直接点击切换。

### 变更与优化 (Changed)
- **闲时内存回收与后台零唤醒优化**：
  - 将欢迎页（`ProZipLandingView`）标题轮播绑定至窗口活跃状态，应用切入后台、失焦或最小化时立即停止定时动画循环，消除后台待机 CPU 唤醒与堆内存碎片。
  - 关闭或收起欢迎窗、设置窗（保留窗口尺寸记忆）、菜单栏文件盒面板、任务进度窗及提示弹窗时主动卸载 `NSHostingView` 视图树并释放图层缓冲；已有活跃归档会话时不再于后台预创建欢迎窗。
  - 将内置资源图片加载器（`ProZipResourceImageLoader`）改为带容量上限的 `NSCache`，设置窗关闭时主动清理缓存；菜单栏状态图标按 `18×18` 尺寸栅格化绘制，避免常驻持有高分辨率原图位图。
- **实时流式压缩进度与引擎预热**：`NativeZipEngine` 支持 512 KiB 分块流式进度上报，`SevenZipEngine` 接入 `-bsp1` 实时压缩进度流并透传 `-mmt` 线程数与 macOS 元数据排除规则（`-xr!.DS_Store/__MACOSX/._*`）；启动时于后台低优先级预热压缩引擎并将压缩执行移出 `@MainActor`。

---

## [0.1.3] - 2026-11-14

### 新增 (Added)
- **Finder 空格键一键呼出 / 关闭 ProZip Mini**：基于系统辅助功能（Accessibility）与自动化（AppleEvents）授权的 `FinderSpacebarMonitor`，在 Finder 中选中支持的压缩包按空格键即可直接打开 ProZip Mini 轻量窗格预览；在 Mini 窗格聚焦时再次按下空格键即可关闭窗格并切回 Finder，支持在「设置 → ProZip Mini」中配置权限引导与接管格式范围。
- **密码本钥匙串授权恢复与兜底重建**：针对开源/自签名版本更新或重签后系统钥匙串 ACL 变更导致原有密码本无法静默解密的问题，保留加密文件并在「设置 → 密码本」及保护设置弹窗提供 **「授权恢复密码本」**（一次性弹窗授权后自动轮换并绑定新签名密钥，后续恢复静默访问）与二次确认 **「清空并重建密码本…」** 兜底入口。

### 变更与优化 (Changed)
- **Mini 窗口头部展示文件体积**：在 ProZip Mini 标题栏副标题中同步展示当前压缩包的条目数量与总文件大小。
- **Touch ID 快捷解锁签名环境适配**：在未配置商业开发者 Team ID 的开源/自签名构建中温和禁用 Touch ID 快捷解锁勾选并提示原因，同时保留完整的 Data Protection Keychain 后端代码以供后续开发者签名构建使用。
- **项目文档演示动图**：在 [README.md](README.md) 中新增交互界面与功能演示 GIF（`Resources/ProZip-Demo.gif`）。

### 修复 (Fixed)
- 修复新建压缩包选项弹窗（`ArchiveCreationDialogView`）顶部标题栏、底部工具栏及空白背景区域无法拖拽移动整个窗口的问题（`WindowDragArea.resolveRootWindow` 沿父窗口链向上定位宿主窗口并结合事件跟踪拖拽）。
- 修复通过 Finder 空格键打开 ProZip Mini 后，再次按下空格键未能关闭 Mini 窗格的问题。

---

## [0.1.2] - 2026-11-12

### 新增 (Added)
- **GitHub Releases 自动更新检测与界面集成**：新增 `AppUpdateService` 模块，支持连接 GitHub Releases API 自动语义化比对最新版本号、展示更新说明摘要，并直接跳转下载最新 `.dmg` / `.zip` 安装包；同步接入「检查更新」弹窗、「设置 → 关于」页与启动自动静默检测（24 小时节流）。
- **macOS 26+ 原生液态玻璃（Liquid Glass）视觉体系**：基于系统原生 `.glassEffect` 与 `GlassEffectContainer` 构建统一的胶囊、圆形及圆角矩形液态玻璃组件，同时保留 macOS 14–15 的毛玻璃平滑回退兼容。

### 变更与优化 (Changed)
- **Mini 浏览窗口光学透射与交互精调**：
  - 校准 Mini 窗口表面原生液态玻璃折射边缘、窗口圆角（`20pt`）与浅/深色桌面背景下的透光度，消除窗口四角灰色边缘伪影。
  - 升级左下角关闭、置顶（含天蓝外圈光环）、展开三个圆形控制钮及右下角「预览 + 全部解压」胶囊为原生交互式液态玻璃，统一鼠标悬停局部柔和染色与按压液态透镜扩张动效。
  - 透明化 Mini 列表右侧滚动条轨道并优化底部渐隐遮罩。
- **完整工作台（Workspace）与欢迎页玻璃控件升级**：
  - 升级右上角视图模式切换胶囊、删除/保存/搜索按钮（含选中态绯红删除玻璃圆钮与展开搜索栏）、路径导航面包屑胶囊及左下角操作栏为原生液态玻璃。
  - 移除主窗口底部静态白色遮罩与操作栏内多余竖向分割线，使底层滚动文件行可直接透过悬浮液态玻璃胶囊实时模糊折射。
  - 优化底部智能 Flow 主按钮边缘玻璃高光与顶部叠层备选胶囊微露视觉，悬停时平滑展开备选「解压」动作。
  - 欢迎窗口「打开压缩包」、「创建压缩包」及「设置」按钮同步切换为原生液态玻璃。

### 修复 (Fixed)
- 修复工作台左下角操作胶囊在鼠标悬停时快捷键徽章（`⏎` / `空格`）因白底白字导致文字不可见的问题。

---

## [0.1.0] - 2026-11-12

### 新增 (Added)
- **首个开源版本发布（GPL-3.0）**：
  - 四层协同解压缩引擎架构：`NativeZipEngine`（纯 Swift 零拷贝直读）、7-Zip（LZMA2 多线程）、系统 `libarchive` 与 `hdiutil` 磁盘映像挂载。
  - 基于 SQLite 的分层极速条目索引（`EntryIndex`），支持大规模归档秒级目录浏览与检索。
  - `1040×740` 三视图完整工作台（图标、列表、分栏）与 `560×422` 轻量 Mini 窗口双模式无缝切换（`⌥⌘M`）。
  - 智能 Flow 上下文动作推荐引擎（应用安装、字体安装、白名单文件安全直开与一键解压）。
  - 常驻菜单栏文件暂存盒（Shelf），支持多源拖拽收集、目录内联穿透浏览与批量归档处理。
  - 本地 AES-GCM 安全密码本，支持系统 Keychain 与 Touch ID 解锁及多密码自动匹配解密。
  - 配套 Finder 右键扩展（`ProZipFinderSync`）与空格键快速预览插件（`ProZipQuickLook`）。

[0.1.5]: https://github.com/scoltzero/prozip/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/scoltzero/prozip/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/scoltzero/prozip/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/scoltzero/prozip/compare/v0.1.0...v0.1.2
[0.1.0]: https://github.com/scoltzero/prozip/releases/tag/v0.1.0
