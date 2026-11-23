# Changelog / 更新日志

All notable changes to **ProZip** will be documented in this file.  
本项目的所有重要变更均记录于此文件中。

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/).  
格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，版本号遵循 [语义化版本 (SemVer)](https://semver.org/lang/zh-CN/)。

---

## [0.1.5] - 2026-11-23

### 🇨🇳 中文

#### 新增 (Added)
- **应用内一键更新（下载、校验并自动重启）**：
  - 在检查更新弹窗中新增「立即更新」能力，无需跳转浏览器手动下载镜像。
  - 直接在应用内流式下载 GitHub Release 中的 `.zip` 安装包并实时显示下载进度，自动校验 `SHA256SUMS.txt` 哈希与 `CFBundleIdentifier`，通过系统 `ditto` 解压并原子替换当前 `ProZip.app`（失败自动回滚备份，目录无写权限时拉起系统授权弹窗）后自动重启新版。

#### 修复与优化 (Fixed & Changed)
- **菜单栏黑白模板图标与弹窗贴边间距修复**：
  - 将状态栏图标改为基于品牌矢量路径绘制的 macOS 黑白模板图标（`isTemplate = true`），去除绿色底色，仅保留主体 **P** 与 33% 透明度折影，自动适配浅色/深色模式及 Retina 分辨率。
  - 收紧菜单栏文件盒面板顶部内边距并锚定菜单栏下沿，消除弹窗与菜单栏之间的多余空隙，同步对齐设置页外观预览。
- **全格式与分卷 RAR 实时解压进度**：修复分卷 RAR 及其他归档格式解压时进度条更新不及时的问题，实现全格式实时流式进度上报。

---

### 🌐 English

#### Added
- **In-App Self-Update (Download, Verify & Relaunch)**:
  - Added one-click **Update Now** inside the Check for Updates dialog so users no longer need to manually download and drag-install from the browser.
  - Streams the GitHub Release `.zip` with live progress, verifies `SHA256SUMS.txt` via `CryptoKit` and validates `CFBundleIdentifier`, extracts via `/usr/bin/ditto`, atomically swaps `ProZip.app` (with rollback on failure and admin prompt when needed), and relaunches automatically.

#### Fixed & Changed
- **Monochrome Template Menu Bar Icon & Shelf Alignment**:
  - Replaced the colored menu bar icon with a resolution-independent macOS template icon (`isTemplate = true`) featuring only the brand **P** and its 33% opacity shadow, adapting automatically to Light and Dark Mode.
  - Tightened the menu bar shelf panel top inset and anchored it to the menu bar bottom edge to eliminate the excessive gap, keeping the Settings preview aligned.
- **Real-Time Extraction Progress**: Streamed live extraction progress across split RAR and all supported archive formats.

---

## [0.1.4] - 2026-11-21

### 🇨🇳 中文

#### 新增 (Added)
- **程序坞图标显示/隐藏设置**：在「设置 → 通用 → 启动」中新增 **「在程序坞中显示」** 开关，支持无需重启实时切换程序坞图标显示与隐藏（动态调整 `NSApplication.ActivationPolicy` 并保持当前活跃窗口焦点）；同时在菜单栏文件盒右键菜单中补充 **「设置…」** 快捷入口，同步提供简中、繁中、英文三语界面文案。
- **任务队列精细清理与独立可缩放创建窗口**：
  - 归档任务队列窗口（`ArchiveProgressWindowView`）新增单条任务移除按钮、一键「清理已完成」（包含失败项）与「全部清空」能力。
  - 创建压缩包配置弹窗（`ArchiveCreationDialogView`）升级为独立可自由调整尺寸的窗口并自动记忆窗口大小；概览卡片中的辅助文件过滤与文件名兼容行支持直接点击切换。

#### 变更与优化 (Changed)
- **闲时内存回收与后台零唤醒优化**：
  - 将欢迎页（`ProZipLandingView`）标题轮播绑定至窗口活跃状态，应用切入后台、失焦或最小化时立即停止定时动画循环，消除后台待机 CPU 唤醒与堆内存碎片。
  - 关闭或收起欢迎窗、设置窗（保留窗口尺寸记忆）、菜单栏文件盒面板、任务进度窗及提示弹窗时主动卸载 `NSHostingView` 视图树并释放图层缓冲；已有活跃归档会话时不再于后台预创建欢迎窗。
  - 将内置资源图片加载器（`ProZipResourceImageLoader`）改为带容量上限的 `NSCache`，设置窗关闭时主动清理缓存；菜单栏状态图标按 `18×18` 尺寸栅格化绘制，避免常驻持有高分辨率原图位图。
- **实时流式压缩进度与引擎预热**：`NativeZipEngine` 支持 512 KiB 分块流式进度上报，`SevenZipEngine` 接入 `-bsp1` 实时压缩进度流并透传 `-mmt` 线程数与 macOS 元数据排除规则（`-xr!.DS_Store/__MACOSX/._*`）；启动时于后台低优先级预热压缩引擎并将压缩执行移出 `@MainActor`。

---

### 🌐 English

#### Added
- **Show / Hide in Dock Preference**: Added a **Show in Dock** toggle under Settings → General → Startup that switches `NSApplication.ActivationPolicy` (`.regular` / `.accessory`) live without restarting while preserving active window focus; added a quick **Settings…** item to the menu bar Box right-click menu, with Simplified Chinese, Traditional Chinese, and English localizations.
- **Granular Task Queue Cleanup & Resizable Standalone Creation Window**:
  - Added per-task dismiss buttons, **Clear Finished** (including failed tasks), and **Clear All** actions in `ArchiveProgressWindowView`.
  - Hosted `ArchiveCreationDialogView` in a resizable standalone window with remembered dimensions, and made overview cleanup/compatibility rows directly interactive toggles.

#### Changed
- **Idle Memory Reclamation & Zero Background Wakeups**:
  - Scoped `ProZipLandingView` headline rotation to `isWindowActive` so backgrounded, unfocused, or minimized windows pause the animation loop immediately with zero idle CPU wakeups.
  - Released `NSHostingView` hierarchies and backing buffers when dismissing the Welcome window, Settings window (preserving remembered size), menu bar Shelf panel, Task Progress panel, and alert windows; avoided eagerly materializing the Welcome window when an archive session is already active.
  - Converted `ProZipResourceImageLoader` to a cost-bounded `NSCache` (purged on Settings window close) and rasterized the menu bar status item icon at `18×18` instead of retaining the full `512×512` source bitmap.
- **Real-Time Streaming Compression Progress & Engine Pre-Warming**: Added 512 KiB chunked progress reporting in `NativeZipEngine` and `-bsp1` live progress streaming in `SevenZipEngine` (forwarding configured `-mmt` thread counts and `-xr!.DS_Store/__MACOSX/._*` exclusions), plus background engine pre-warming off `@MainActor`.

---

## [0.1.3] - 2026-11-14

### 🇨🇳 中文

#### 新增 (Added)
- **Finder 空格键一键呼出 / 关闭 ProZip Mini**：基于系统辅助功能（Accessibility）与自动化（AppleEvents）授权的 `FinderSpacebarMonitor`，在 Finder 中选中支持的压缩包按空格键即可直接打开 ProZip Mini 轻量窗格预览；在 Mini 窗格聚焦时再次按下空格键即可关闭窗格并切回 Finder，支持在「设置 → ProZip Mini」中配置权限引导与接管格式范围。
- **密码本钥匙串授权恢复与兜底重建**：针对开源/自签名版本更新或重签后系统钥匙串 ACL 变更导致原有密码本无法静默解密的问题，保留加密文件并在「设置 → 密码本」及保护设置弹窗提供 **「授权恢复密码本」**（一次性弹窗授权后自动轮换并绑定新签名密钥，后续恢复静默访问）与二次确认 **「清空并重建密码本…」** 兜底入口。

#### 变更与优化 (Changed)
- **Mini 窗口头部展示文件体积**：在 ProZip Mini 标题栏副标题中同步展示当前压缩包的条目数量与总文件大小。
- **Touch ID 快捷解锁签名环境适配**：在未配置商业开发者 Team ID 的开源/自签名构建中温和禁用 Touch ID 快捷解锁勾选并提示原因，同时保留完整的 Data Protection Keychain 后端代码以供后续开发者签名构建使用。
- **项目文档演示动图**：在 `README.md` 中新增交互界面与功能演示 GIF（`Resources/ProZip-Demo.gif`）。

#### 修复 (Fixed)
- 修复新建压缩包选项弹窗（`ArchiveCreationDialogView`）顶部标题栏、底部工具栏及空白背景区域无法拖拽移动整个窗口的问题（`WindowDragArea.resolveRootWindow` 沿父窗口链向上定位宿主窗口并结合事件跟踪拖拽）。
- 修复通过 Finder 空格键打开 ProZip Mini 后，再次按下空格键未能关闭 Mini 窗格的问题。

---

### 🌐 English

#### Added
- **Finder Spacebar Toggle for ProZip Mini**: Added `FinderSpacebarMonitor` using macOS Accessibility & Automation (AppleEvents) permissions so pressing Spacebar in Finder on a supported archive opens ProZip Mini directly, and pressing Spacebar again inside Mini dismisses the window and returns focus to Finder—configurable with permission onboarding and scope toggles in Settings → ProZip Mini.
- **Password Book Keychain Authorization Recovery & Reset Fallback**: Preserves existing encrypted vaults when an open-source / ad-hoc re-signed binary invalidates legacy Keychain ACLs; added **Authorize & Recover Password Book** (prompts once via system Keychain UI, decrypts saved entries, and rotates onto a new key bound to the current app signature for silent future launches) alongside a two-step **Reset & Rebuild Password Book** fallback in Settings → Password Book and the protection dialog.

#### Changed
- **Archive Size in ProZip Mini Header**: Updated the Mini window subtitle to display both item count and formatted archive file size.
- **Ad-Hoc Build Handling for Touch ID Quick Unlock**: Gracefully disables the Touch ID quick-unlock toggle in builds without an Apple Team ID while keeping the full Data Protection Keychain implementation intact for future signed commercial builds.
- **Interactive Demo GIF in README**: Added `Resources/ProZip-Demo.gif` showcasing UI modes and workflows.

#### Fixed
- Fixed an issue where dragging the header, footer, or background area of the archive creation options sheet (`ArchiveCreationDialogView`) did not move the host window (`WindowDragArea.resolveRootWindow` parent-chain resolution + mouse drag tracking).
- Fixed Spacebar not dismissing the ProZip Mini window after launching via Finder Spacebar preview.

---

## [0.1.2] - 2026-11-12

### 🇨🇳 中文

#### 新增 (Added)
- **GitHub Releases 自动更新检测与界面集成**：新增 `AppUpdateService` 模块，支持连接 GitHub Releases API 自动语义化比对最新版本号、展示更新说明摘要，并直接跳转下载最新 `.dmg` / `.zip` 安装包；同步接入「检查更新」弹窗、「设置 → 关于」页与启动自动静默检测（24 小时节流）。
- **macOS 26+ 原生液态玻璃（Liquid Glass）视觉体系**：基于系统原生 `.glassEffect` 与 `GlassEffectContainer` 构建统一的胶囊、圆形及圆角矩形液态玻璃组件，同时保留 macOS 14–15 的毛玻璃平滑回退兼容。

#### 变更与优化 (Changed)
- **Mini 浏览窗口光学透射与交互精调**：
  - 校准 Mini 窗口表面原生液态玻璃折射边缘、窗口圆角（`20pt`）与浅/深色桌面背景下的透光度，消除窗口四角灰色边缘伪影。
  - 升级左下角关闭、置顶（含天蓝外圈光环）、展开三个圆形控制钮及右下角「预览 + 全部解压」胶囊为原生交互式液态玻璃，统一鼠标悬停局部柔和染色与按压液态透镜扩张动效。
  - 透明化 Mini 列表右侧滚动条轨道并优化底部渐隐遮罩。
- **完整工作台（Workspace）与欢迎页玻璃控件升级**：
  - 升级右上角视图模式切换胶囊、删除/保存/搜索按钮（含选中态绯红删除玻璃圆钮与展开搜索栏）、路径导航面包屑胶囊及左下角操作栏为原生液态玻璃。
  - 移除主窗口底部静态白色遮罩与操作栏内多余竖向分割线，使底层滚动文件行可直接透过悬浮液态玻璃胶囊实时模糊折射。
  - 优化底部智能 Flow 主按钮边缘玻璃高光与顶部叠层备选胶囊微露视觉，悬停时平滑展开备选「解压」动作。
  - 欢迎窗口「打开压缩包」、「创建压缩包」及「设置」按钮同步切换为原生液态玻璃。

#### 修复 (Fixed)
- 修复工作台左下角操作胶囊在鼠标悬停时快捷键徽章（`⏎` / `空格`）因白底白字导致文字不可见的问题。

---

### 🌐 English

#### Added
- **GitHub Releases Auto-Update Service & UI Integration**: Introduced `AppUpdateService` to query the GitHub Releases API, perform semantic version comparison, display release note summaries, and open direct `.dmg` / `.zip` download links—integrated across the Check for Updates dialog, Settings → About pane, and 24-hour throttled silent launch checks.
- **Native macOS 26+ Liquid Glass Design System**: Built unified capsule, circular, and continuous-corner Liquid Glass modifiers powered by native `.glassEffect` and `GlassEffectContainer`, with graceful frosted-material fallbacks for macOS 14–15.

#### Changed
- **Mini Window Optical Refraction & Interaction Polish**:
  - Calibrated Mini window Liquid Glass edge refraction, `20pt` continuous corner radius, and light/dark backdrop translucency, eliminating corner frame artifacts.
  - Upgraded the bottom-left circular controls (Close, Pin with sky-blue halo ring, Expand) and bottom-right `Preview + Extract All` capsule to native interactive Liquid Glass with smooth per-segment hover tinting and directional press lens response.
  - Made the Mini vertical scroller slot transparent and refined the bottom progressive fade mask.
- **Workspace & Welcome Window Liquid Glass Upgrade**:
  - Upgraded the top-right view-switcher capsule, Delete/Save/Search circular buttons (including active crimson Delete glass button and expanded search bar), breadcrumb navigation pill, and bottom-left action bar to native Liquid Glass.
  - Removed the static bottom white veil and redundant vertical dividers in Workspace mode so scrolled file rows refract directly through the floating Liquid Glass capsule.
  - Refined the primary Flow CTA's luminous glass rim and stacked peek card indicator, smoothly expanding the secondary `Extract` action on hover.
  - Unified the Welcome window's `Open Archive`, `Create Archive`, and `Settings` controls with native Liquid Glass.

#### Fixed
- Fixed an issue where keyboard shortcut keycap badges (`⏎` / `Space`) inside the Workspace bottom action capsule turned white-on-white when hovered.

---

## [0.1.0] - 2026-11-12

### 🇨🇳 中文

#### 新增 (Added)
- **首个开源版本发布（GPL-3.0）**：
  - 四层协同解压缩引擎架构：`NativeZipEngine`（纯 Swift 零拷贝直读）、7-Zip（LZMA2 多线程）、系统 `libarchive` 与 `hdiutil` 磁盘映像挂载。
  - 基于 SQLite 的分层极速条目索引（`EntryIndex`），支持大规模归档秒级目录浏览与检索。
  - `1040×740` 三视图完整工作台（图标、列表、分栏）与 `560×422` 轻量 Mini 窗口双模式无缝切换（`⌥⌘M`）。
  - 智能 Flow 上下文动作推荐引擎（应用安装、字体安装、白名单文件安全直开与一键解压）。
  - 常驻菜单栏文件暂存盒（Shelf），支持多源拖拽收集、目录内联穿透浏览与批量归档处理。
  - 本地 AES-GCM 安全密码本，支持系统 Keychain 与 Touch ID 解锁及多密码自动匹配解密。
  - 配套 Finder 右键扩展（`ProZipFinderSync`）与空格键快速预览插件（`ProZipQuickLook`）。

### 🌐 English

#### Added
- **Initial Open Source Release (GPL-3.0)**:
  - Four-tier archive engine architecture combining `NativeZipEngine` (zero-copy pure Swift ZIP reader), 7-Zip (multi-threaded LZMA2), system `libarchive`, and `hdiutil` disk image mounting.
  - High-speed hierarchical SQLite entry indexing (`EntryIndex`) for instant browsing and search across large archives.
  - Dual-mode workflow switching seamlessly (`⌥⌘M`) between the `1040×740` multi-view Workspace (Icons, List, Columns) and the `560×422` compact Mini browser.
  - Context-aware Flow recommendation engine (app bundle installation, font installation, safe allowlisted direct open, and one-click extraction).
  - Persistent menu bar Shelf for multi-source drag-and-drop staging, inline folder/archive browsing, and batch compression/extraction.
  - Local AES-GCM encrypted Password Book backed by macOS Keychain, Touch ID unlocking, and automatic password matching.
  - Bundled Finder context-menu extension (`ProZipFinderSync`) and Quick Look preview extension (`ProZipQuickLook`).

[0.1.4]: https://github.com/scoltzero/prozip/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/scoltzero/prozip/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/scoltzero/prozip/compare/v0.1.0...v0.1.2
[0.1.0]: https://github.com/scoltzero/prozip/releases/tag/v0.1.0
