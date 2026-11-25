<p align="center">
  <img src="Resources/AppIcon-Preview.png" alt="ProZip Logo" width="160">
</p>

<h1 align="center">ProZip</h1>

<p align="center">
  <strong>A Modern, Elegant, and High-Performance Open-Source Archive Manager for macOS</strong><br>
  Built with Native Swift &amp; SwiftUI · Four-Tier Engine Pipeline · Instant SQLite Indexing · Deep System Extensions
</p>

<p align="center">
  <strong>English</strong> ·
  <a href="i18n/zh-CN/README.md">简体中文</a> ·
  <a href="i18n/zh-TW/README.md">繁體中文</a> ·
  <a href="i18n/ja/README.md">日本語</a> ·
  <a href="i18n/ko/README.md">한국어</a> ·
  <a href="i18n/es/README.md">Español</a> ·
  <a href="i18n/fr/README.md">Français</a> ·
  <a href="i18n/de/README.md">Deutsch</a> ·
  <a href="i18n/ru/README.md">Русский</a>
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
  <a href="https://github.com/scoltzero/prozip/releases/latest"><img src="https://img.shields.io/badge/Download-Latest%20Release-0969DA?style=for-the-badge&logo=github&logoColor=white" alt="Download Latest Release"></a>
  <a href="#quick-start"><img src="https://img.shields.io/badge/Guide-Quick%20Start-334155?style=for-the-badge&logo=readthedocs&logoColor=white" alt="Quick Start"></a>
  <a href="https://github.com/scoltzero/prozip/issues"><img src="https://img.shields.io/badge/Feedback-Issues-2EA44F?style=for-the-badge&logo=github&logoColor=white" alt="Feedback & Issues"></a>
</p>

<p align="center">
  <img src="Resources/ProZip-Demo.gif" alt="ProZip UI & Feature Showcase" width="920">
</p>

> [!IMPORTANT]
> **Project Positioning & Purpose**:
> ProZip is an independent, fully open-source project created for learning, research, and technical exploration of modern macOS desktop architecture, hybrid SwiftUI + AppKit interaction design, cross-engine archive streaming pipelines, and clean-room software engineering.
>
> This software is intended for technical exchange and educational purposes only, and is not meant to compete with any commercial archiving software on the market. Every line of code is independently written from scratch without decompiled commercial source code or unauthorized assets, and is released under the [GNU General Public License v3.0](LICENSE). Fellow macOS developers and open-source contributors are warmly welcome to explore, discuss, and improve it together.

---

## Why ProZip

| Core Feature | Description |
|---|---|
| **Native Performance & Polish** | Crafted in pure Swift & SwiftUI with deep macOS visual hierarchy, Liquid Glass optics, and responsive tactile feedback. |
| **Four-Tier Engine Synergy** | Combines `NativeZipEngine` (zero-copy direct reader), 7-Zip (multi-threaded LZMA2), system `libarchive`, and `hdiutil` disk image mounting. |
| **Instant Dual-Table SQLite Indexing** | Builds a local hierarchical index database upon opening an archive—expand, filter, and selectively extract tens of thousands of entries in milliseconds. |
| **Flexible Dual-Mode Workspace** | Switch seamlessly (`⌥⌘M`) between the full-featured `1040×740` multi-column Workspace and the compact `560×422` frosted Mini browser. |
| **Smart Context-Aware Flow** | Automatically inspects archive contents (apps, fonts, documents, etc.) and recommends contextual actions like **Install to Applications**, **Install Font**, or direct open. |
| **Menu Bar Staging Shelf (ProZip Box)** | Always-available menu bar drop zone for collecting files from multiple folders, browsing directories inline, and batch compressing in one click. |
| **Secure Password Book & Touch ID** | Local AES-GCM encrypted password vault protected by macOS Keychain and Touch ID, with automatic multi-password rotation when unlocking archives. |
| **Deep System Extensions** | Ships with a Finder context-menu extension (`FinderSync`) and a Spacebar `Quick Look` instant preview plugin. |

---

## Format Support Matrix

| Category | Supported Formats & Capabilities |
|---|---|
| **Extraction & Browsing** | ZIP, 7Z, RAR (v4 / v5 / multi-volume), TAR, GZ, TGZ, BZ2, TBZ2, XZ, TXZ, ZST, TZST, CPIO, CAB, ISO, DMG, and more |
| **Archive Creation** | ZIP (configurable Deflate compression level, AES-256 encryption, split volumes), 7Z (high-ratio LZMA2, header encryption, split volumes), TAR |
| **In-Place Editing & Saving** | Add, delete, and rename entries directly inside existing single-volume archives with atomic commit transactions and automatic rollback protection |

---

## System Requirements

- **Operating System**: macOS 14.0 (Sonoma) or later
- **Architecture**: Native Apple Silicon (M-series) and Intel (`x86_64`) compatibility
- **Privacy & Environment**: 100% local offline execution—zero network tracking, telemetry, or remote analytics enabled by default

---

## Quick Start

### 1. Download a Prebuilt Release
Head over to the [Latest Release](https://github.com/scoltzero/prozip/releases/latest) page to download `ProZip-v0.1.5-macos.dmg` or `ProZip-v0.1.5-macos.zip` (see [CHANGELOG.md](CHANGELOG.md) for release notes).

### 2. Install & Launch
1. Open the `.dmg` disk image and drag `ProZip.app` into your `Applications` folder.
2. Double-click to open ProZip. If macOS displays an unidentified developer prompt, go to **System Settings → Privacy & Security** and click **Open Anyway**.
3. Follow the first-launch onboarding wizard to enable the Finder extension and Quick Look preview plugin as needed.

---

## Architecture

ProZip adopts a clean layered architecture that decouples UI presentation, session state, entry indexing, and low-level archive engines:

```text
┌─────────────────────────────────────────────────────────────┐
│              ProZip App & Extensions Layer                  │
│   (WorkspaceWindowView / MiniWindowView / MenuBarShelf)     │
│   (ProZipFinderSync Extension / ProZipQuickLook Plugin)     │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    ProZipUI & ViewModels                    │
│   - AppViewModel (Session orchestration & Flow decisions)   │
│   - ProZipTheme (Native styling, color hierarchy, motion)   │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    ProZipCore Engine Layer                  │
│   - ArchiveBrowsingSession (Session lifecycle & staging)    │
│   - EntryIndex (High-speed SQLite directory & entry index)  │
│   - PasswordBook (AES-GCM + Keychain + Touch ID vault)      │
│   - ManagedTemporaryArtifactRegistry (Temp file governance) │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                   Archive Engine Broker                     │
│   ├─ NativeZipEngine   : Pure Swift direct reader & writer  │
│   ├─ SevenZipEngine    : 7-Zip LZMA2 / AES / wide formats   │
│   ├─ LibarchiveEngine  : System libarchive streaming layer  │
│   └─ DiskImageEngine   : hdiutil disk image mounting        │
└─────────────────────────────────────────────────────────────┘
```

---

## Building from Source

ProZip is managed with Swift Package Manager and includes automated packaging scripts:

### Prerequisites
- macOS 14.0+ with Xcode 15+ or Xcode Command Line Tools installed
- `7zz` installed via Homebrew (used to bundle the embedded 7-Zip engine subset):
  ```bash
  brew install sevenzip
  ```

### Build Steps
1. **Clone the repository**:
   ```bash
   git clone https://github.com/scoltzero/prozip.git
   cd prozip
   ```

2. **Compile core Swift modules**:
   ```bash
   swift build -c release
   ```

3. **Package the complete macOS `.app` bundle** (including Finder Sync and Quick Look extensions):
   ```bash
   bash scripts/build_app.sh release
   ```
   Once finished, the packaged app bundle is available at `build/ProZip.app`.

---

## Independent Implementation & Open-Source Statement

<details>
<summary><strong>Click to expand design philosophy &amp; clean-room boundaries</strong></summary>

1. **Research & Learning Purpose**:
   ProZip was started to explore the frontiers of modern macOS desktop GUI engineering. During development, we studied interaction patterns, animation cadence, multi-engine routing, and streaming pipelines across leading archive utilities in the industry, then independently designed and implemented everything in pure Swift and SwiftUI.

2. **Clean-Room Engineering**:
   This repository contains zero decompiled source code, protected assets, or private certificates from any proprietary software. All business logic, data structures, and UI views are authored from scratch under clean-room engineering principles.

3. **Open Exchange & Non-Commercial Intent**:
   This project is open-sourced to foster technical exchange among developers interested in macOS desktop apps, filesystem streaming, and native C/Swift interoperability. We deeply respect the intellectual property and craftsmanship of all commercial software authors, and this repository does not aim to replace any commercial product.

</details>

---

## Credits & Acknowledgments

ProZip builds upon outstanding open-source infrastructure and libraries. Sincere thanks to the maintainers of these projects:

| Project | Role & Contribution | License |
|---|---|---|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | Native Swift ZIP parsing and streaming read/write foundation | MIT |
| [7-Zip / p7zip](https://www.7-zip.org/) | 7z, LZMA2 compression, and multi-format extraction engine | LGPL-2.1+ / unRAR License |
| [libarchive](https://www.libarchive.org/) | Multi-format streaming archive compatibility layer | BSD |
| [libdeflate](https://github.com/ebiggers/libdeflate) | High-performance Deflate / zlib compression reference | MIT |

---

## Support & Community

If you enjoy ProZip or find it helpful for learning or daily workflows:
- Give the repository a **Star** ⭐️ on GitHub to show your support!
- Found a bug or have an idea? Feel free to open an [Issue](https://github.com/scoltzero/prozip/issues) or submit a Pull Request!

---

## License

ProZip core source code is licensed under the **[GNU General Public License v3.0](LICENSE)** (GPL-3.0).  
Referenced third-party open-source components remain governed by their respective upstream licenses.
