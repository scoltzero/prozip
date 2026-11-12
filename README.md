<p align="center">
  <img src="Resources/AppIcon-Preview.png" alt="ProZip Logo" width="160">
</p>

<h1 align="center">ProZip</h1>

<p align="center">
  <strong>现代、优雅且高性能的 macOS 开源解压缩与归档管理工具</strong><br>
  原生 Swift / SwiftUI 打造 · 四层引擎深度融合 · SQLite 极速索引 · 系统级扩展集成
</p>

<p align="center">
  <a href="https://github.com/scoltzero/prozip/stargazers"><img src="https://img.shields.io/github/stars/scoltzero/prozip?style=flat-square&logo=github&label=Stars" alt="GitHub Stars"></a>
  <a href="https://github.com/scoltzero/prozip/forks"><img src="https://img.shields.io/github/forks/scoltzero/prozip?style=flat-square&logo=github&label=Forks" alt="GitHub Forks"></a>
  <a href="https://github.com/scoltzero/prozip/releases"><img src="https://img.shields.io/github/downloads/scoltzero/prozip/total?style=flat-square&label=Downloads" alt="GitHub Downloads"></a>
  <a href="https://github.com/scoltzero/prozip/releases/latest"><img src="https://img.shields.io/github/v/release/scoltzero/prozip?style=flat-square&label=Release" alt="Latest Release"></a>
  <a href="https://developer.apple.com/macos/"><img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="Platform macOS 14+"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/scoltzero/prozip?style=flat-square&label=License" alt="License"></a>
</p>

<p align="center">
  <a href="https://github.com/scoltzero/prozip/releases/latest"><img src="https://img.shields.io/badge/Download-Latest%20Release-0969DA?style=for-the-badge&logo=github&logoColor=white" alt="下载最新版本"></a>
  <a href="#快速开始"><img src="https://img.shields.io/badge/Guide-Quick%20Start-334155?style=for-the-badge&logo=readthedocs&logoColor=white" alt="快速开始"></a>
  <a href="https://github.com/scoltzero/prozip/issues"><img src="https://img.shields.io/badge/Feedback-Issues-2EA44F?style=for-the-badge&logo=github&logoColor=white" alt="问题反馈与建议"></a>
</p>

> [!IMPORTANT]
> **关于本项目的定位与初衷**：
> 本项目为开发者个人出于对 macOS 现代化桌面应用架构、SwiftUI 与 AppKit 混合交互设计、跨引擎归档流（Archive Streaming Pipeline）及清洁室工程实践的学习、研究与技术探索而发起的完全开源项目。
> 
> 本软件仅供技术交流与学习使用，无意与市面上任何成熟的商业归档软件构成竞争。所有代码均由个人独立编写，不包含任何商业逆向源码或非授权素材，全量源码均遵循 [GNU General Public License v3.0](LICENSE) 协议公开。欢迎广大 macOS 开发者与开源爱好者交流探讨、指正与共同完善。

---

## 为什么选择 ProZip

| 核心特性 | 说明 |
|---|---|
| **原生性能与体验** | 纯 Swift / SwiftUI 打造，深度融合 macOS 原生外观、触控反馈与视觉层级，轻快敏捷。 |
| **四层引擎深度协同** | 结合 NativeZipEngine（零拷贝直读）、7-Zip (LZMA2 多线程)、系统 libarchive 与 hdiutil 磁盘挂载。 |
| **SQLite 双表极速索引** | 归档加载即在本地建立分层索引数据库，数万条目秒级展开、过滤与局部提取，告别漫长解包等待。 |
| **双模式灵活工作台** | 支持 1040×740 多栏全功能工作台与 560×422 磨砂 Mini 浏览窗口无缝切换（快捷键 `⌥⌘M`）。 |
| **智能 Flow 动作流** | 上下文自动识别归档内容（应用、字体、文档等），智能推荐「安装到应用程序」、「安装字体」或直开。 |
| **菜单栏暂存盒 (Shelf)** | 常驻菜单栏的敏捷暂存工作区，支持拖拽收集多源散落文件、目录内联穿透浏览与批量一键压缩。 |
| **安全密码本与 Touch ID** | 本地 AES-GCM 密码安全管理，支持系统 Keychain 与 Touch ID 硬件解锁保护，多密码自动轮询匹配。 |
| **系统级深度扩展** | 配套 Finder 右键上下文菜单扩展（FinderSync）与空格键 Quick Look 极速预览插件。 |

---

## 格式支持矩阵

| 类别 | 支持格式与能力 |
|---|---|
| **主流解压与浏览** | ZIP, 7Z, RAR (v4 / v5 / 分卷), TAR, GZ, TGZ, BZ2, TBZ2, XZ, TXZ, ZST, TZST, CPIO, CAB, ISO, DMG 等 |
| **归档与压缩创建** | ZIP (支持 Deflate 速度与压缩比调节、AES-256 加密、分卷切片)、7Z (LZMA2 高压缩比、Header 加密、分卷)、TAR |
| **原位修改与保存** | 支持对现有非分卷归档直接添加、删除、重命名文件并安全原子提交（带发布事务与回滚保障） |

---

## 平台与系统要求

- **操作系统**：macOS 14.0 (Sonoma) 及以上
- **处理器架构**：Apple Silicon (M 系列芯片) 原生运行与 Intel (x86_64) 通用兼容
- **权限与环境**：纯本地运行，默认不开启任何联网追踪、遥测或远程统计

---

## 快速开始

### 1. 下载预编译版本
前往 [Latest Release](https://github.com/scoltzero/prozip/releases/latest) 页面下载 `ProZip-v0.1.2-macos.dmg` 或 `ProZip-v0.1.2-macos.zip`。

### 2. 安装与运行
1. 打开 DMG 磁盘映像，将 `ProZip.app` 拖入 `Applications`（应用程序）文件夹。
2. 双击打开 ProZip。如遇系统安全提示，可在「系统设置 → 隐私与安全性」中点击「仍要打开」。
3. 首次启动时可根据向导提示开启 Finder 扩展与 Quick Look 预览插件。

---

## 架构与技术实现

ProZip 采用清晰的分层架构，将界面交互、业务状态、会话索引与底层解压缩引擎完全解耦：

```text
┌─────────────────────────────────────────────────────────────┐
│              ProZip App & Extensions Layer                  │
│   (WorkspaceWindowView / MiniWindowView / MenuBarShelf)     │
│   (ProZipFinderSync Extension / ProZipQuickLook Plugin)     │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    ProZipUI & ViewModels                    │
│   - AppViewModel (会话驱动、状态流转、Flow 动作决策)        │
│   - ProZipTheme (原生风格、色彩层级、动画反馈)              │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    ProZipCore Engine Layer                  │
│   - ArchiveBrowsingSession (会话生命周期与安全暂存管理)     │
│   - EntryIndex (SQLite 极速目录与条目索引表)                │
│   - PasswordBook (AES-GCM + Keychain + Touch ID 密码金库)   │
│   - ManagedTemporaryArtifactRegistry (临时产物生命周期治理) │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                   Archive Engine Broker                     │
│   ├─ NativeZipEngine   : 纯 Swift 原生直读与快速写入        │
│   ├─ SevenZipEngine    : 7-Zip LZMA2 / AES / 宽格式子系统   │
│   ├─ LibarchiveEngine  : 系统 libarchive 兼容流引擎         │
│   └─ DiskImageEngine   : hdiutil 磁盘映像与挂载管理         │
└─────────────────────────────────────────────────────────────┘
```

---

## 本地编译与开发

本项目使用标准 Swift Package Manager 管理依赖，并提供自动化构建脚本：

### 前置依赖
- macOS 14.0+，已安装 Xcode 15+ 或 Command Line Tools
- Homebrew 安装的 7zz 工具（用于提取内置引擎子集）：
  ```bash
  brew install sevenzip
  ```

### 构建步骤
1. **克隆代码仓库**：
   ```bash
   git clone https://github.com/scoltzero/prozip.git
   cd prozip
   ```

2. **编译 Swift 核心模块**：
   ```bash
   swift build -c release
   ```

3. **打包完整 macOS Application 产物**（含 Finder 扩展与 Quick Look）：
   ```bash
   bash scripts/build_app.sh release
   ```
   打包完成后，产物位于 `build/ProZip.app`。

---

## 独立实现与开源交流说明

<details>
<summary><strong>展开查看设计理念与著作权边界说明</strong></summary>

1. **研发宗旨与学习初衷**：
   本项目的开发初衷在于探索 macOS 现代桌面 GUI 开发的极限体验。我们在开发中研究了业界大量优秀归档工具在交互设计、动画节奏、多引擎调度与流式处理上的先进思路，并通过纯 Swift / SwiftUI 进行了独立设计与编码实现。

2. **独立编写与清洁室原则**：
   本项目不包含任何商业专有软件的反编译源码、受保护资源或私有证书。所有业务逻辑、数据结构、UI 视图代码均从零编写，符合 Clean Room 软件工程原则。

3. **友善交流与非竞争承诺**：
   开源此项目的目的是为了与社区中对 macOS 桌面开发、文件系统流处理、原生跨语言互操作感兴趣的开发者互相交流与学习。我们充分尊重所有商业软件开发者的知识产权与辛勤劳动，本仓库不以替代任何商业软件为目的。

</details>

---

## 来源与鸣谢

ProZip 的实现离不开开源社区优秀基础设施与工具库的支持，特此向以下开源项目与维护者致以诚挚感谢：

| 开源项目 | 用途与贡献 | 开源协议 |
|---|---|---|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | 原生 Swift ZIP 结构解析与流式读写基础 | MIT |
| [7-Zip / p7zip](https://www.7-zip.org/) | 7z、LZMA2 算法与多格式解包引擎 | LGPL-2.1+ / unRAR License |
| [libarchive](https://www.libarchive.org/) | 多格式流式归档兼容层 | BSD |
| [libdeflate](https://github.com/ebiggers/libdeflate) | 高性能 Deflate / zlib 解压缩参考 | MIT |

---

## 支持与交流

如果你喜欢 ProZip，或者它在学习和日常使用中对你有所帮助：
- 欢迎在 GitHub 上点亮一颗 **Star** ⭐️ 支持项目！
- 发现 Bug 或有改进建议？欢迎随时提交 [Issues](https://github.com/scoltzero/prozip/issues) 或 Pull Request！

---

## 许可证

ProZip 核心代码基于 **[GNU General Public License v3.0](LICENSE)** (GPL-3.0) 协议开源。
引用的第三方开源组件继续遵循其各自的上游开源许可证。
