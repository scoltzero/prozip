# Changelog

All notable changes to **ProZip** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/lang/zh-CN/).

## [0.1.2] - 2026-11-12

### Added
- **GitHub Releases 自动更新检测后端与界面集成**：新增 `AppUpdateService` 模块，支持连接 GitHub Releases API 自动语义化比对最新版本号、展示更新说明摘要，并直接跳转下载最新 `.dmg` / `.zip` 安装包；同步接入「检查更新」弹窗、「设置 → 关于」页与启动自动静默检测（24 小时节流）。
- **macOS 26+ 原生液态玻璃（Liquid Glass）视觉体系**：基于系统原生 `.glassEffect` 与 `GlassEffectContainer` 构建统一的胶囊、圆形及圆角矩形液态玻璃组件，同时保留 macOS 14–15 的毛玻璃平滑回退兼容。

### Changed
- **Mini 浏览窗口光学透射与交互精调**：
  - 校准 Mini 窗口表面原生液态玻璃折射边缘、窗口圆角（`20pt`）与浅/深色桌面背景下的透光度，消除窗口四角灰色边缘伪影。
  - 升级左下角关闭、置顶（含天蓝外圈光环）、展开三个圆形控制钮及右下角「预览 + 全部解压」胶囊为原生交互式液态玻璃，统一鼠标悬停局部柔和染色与按压液态透镜扩张动效。
  - 将 Mini 列表右侧滚动条轨道透明化并优化底部渐隐遮罩。
- **完整工作台（Workspace）与欢迎页玻璃控件升级**：
  - 升级右上角视图模式切换胶囊、删除/保存/搜索按钮（含选中态绯红删除玻璃圆钮与展开搜索栏）、路径导航面包屑胶囊及左下角操作栏为原生液态玻璃。
  - 移除主窗口底部静态白色遮罩与操作栏内多余竖向分割线，使底层滚动文件行可直接透过悬浮液态玻璃胶囊实时模糊折射。
  - 优化底部智能 Flow 主按钮边缘玻璃高光与顶部叠层备选胶囊微露视觉，悬停时平滑展开备选「解压」动作。
  - 欢迎窗口「打开压缩包」、「创建压缩包」及「设置」按钮同步切换为原生液态玻璃。

### Fixed
- 修复工作台左下角操作胶囊在鼠标悬停时快捷键徽章（`⏎` / `空格`）因白底白字导致文字不可见的问题。

---

## [0.1.0] - 2026-11-12

### Added
- **首个开源版本发布（GPL-3.0）**：
  - 四层协同解压缩引擎架构：`NativeZipEngine`（纯 Swift 零拷贝直读）、7-Zip（LZMA2 多线程）、系统 `libarchive` 与 `hdiutil` 磁盘映像挂载。
  - 基于 SQLite 的分层极速条目索引（`EntryIndex`），支持大规模归档秒级目录浏览与检索。
  - `1040×740` 三视图完整工作台（图标、列表、分栏）与 `560×422` 轻量 Mini 窗口双模式无缝切换（`⌥⌘M`）。
  - 智能 Flow 上下文动作推荐引擎（应用安装、字体安装、白名单文件安全直开与一键解压）。
  - 常驻菜单栏文件暂存盒（Shelf），支持多源拖拽收集、目录内联穿透浏览与批量归档处理。
  - 本地 AES-GCM 安全密码本，支持系统 Keychain 与 Touch ID 解锁及多密码自动匹配解密。
  - 配套 Finder 右键扩展（`ProZipFinderSync`）与空格键快速预览插件（`ProZipQuickLook`）。

[0.1.2]: https://github.com/scoltzero/prozip/compare/v0.1.0...v0.1.2
[0.1.0]: https://github.com/scoltzero/prozip/releases/tag/v0.1.0
