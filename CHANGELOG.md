# Changelog / 更新日志

All notable changes to **ProZip** will be documented in this file.  
本项目的所有重要变更均记录于此文件中。

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/).  
格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 规范，版本号遵循 [语义化版本 (SemVer)](https://semver.org/lang/zh-CN/)。

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

[0.1.2]: https://github.com/scoltzero/prozip/compare/v0.1.0...v0.1.2
[0.1.0]: https://github.com/scoltzero/prozip/releases/tag/v0.1.0
