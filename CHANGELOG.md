# Changelog

**English** · [简体中文](i18n/zh-CN/CHANGELOG.md) · [繁體中文](i18n/zh-TW/CHANGELOG.md) · [日本語](i18n/ja/CHANGELOG.md) · [한국어](i18n/ko/CHANGELOG.md) · [Español](i18n/es/CHANGELOG.md) · [Français](i18n/fr/CHANGELOG.md) · [Deutsch](i18n/de/CHANGELOG.md) · [Русский](i18n/ru/CHANGELOG.md)

All notable changes to **ProZip** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

---

## [0.1.5] - 2026-11-23

### Added
- **In-App Self-Update (Download, Verify & Relaunch)**:
  - Added one-click **Update Now** inside the Check for Updates dialog so users no longer need to manually download and drag-install from the browser.
  - Streams the GitHub Release `.zip` with live progress, verifies `SHA256SUMS.txt` via `CryptoKit` and validates `CFBundleIdentifier`, extracts via `/usr/bin/ditto`, atomically swaps `ProZip.app` (with rollback on failure and admin prompt when needed), and relaunches automatically.

### Fixed & Changed
- **Monochrome Template Menu Bar Icon & Shelf Alignment**:
  - Replaced the colored menu bar icon with a resolution-independent macOS template icon (`isTemplate = true`) featuring only the brand **P** and its 33% opacity shadow, adapting automatically to Light and Dark Mode.
  - Tightened the menu bar shelf panel top inset and anchored it to the menu bar bottom edge to eliminate the excessive gap, keeping the Settings preview aligned.
- **Real-Time Extraction Progress**: Streamed live extraction progress across split RAR and all supported archive formats.

---

## [0.1.4] - 2026-11-21

### Added
- **Show / Hide in Dock Preference**: Added a **Show in Dock** toggle under Settings → General → Startup that switches `NSApplication.ActivationPolicy` (`.regular` / `.accessory`) live without restarting while preserving active window focus; added a quick **Settings…** item to the menu bar Box right-click menu, with Simplified Chinese, Traditional Chinese, and English localizations.
- **Granular Task Queue Cleanup & Resizable Standalone Creation Window**:
  - Added per-task dismiss buttons, **Clear Finished** (including failed tasks), and **Clear All** actions in `ArchiveProgressWindowView`.
  - Hosted `ArchiveCreationDialogView` in a resizable standalone window with remembered dimensions, and made overview cleanup/compatibility rows directly interactive toggles.

### Changed
- **Idle Memory Reclamation & Zero Background Wakeups**:
  - Scoped `ProZipLandingView` headline rotation to `isWindowActive` so backgrounded, unfocused, or minimized windows pause the animation loop immediately with zero idle CPU wakeups.
  - Released `NSHostingView` hierarchies and backing buffers when dismissing the Welcome window, Settings window (preserving remembered size), menu bar Shelf panel, Task Progress panel, and alert windows; avoided eagerly materializing the Welcome window when an archive session is already active.
  - Converted `ProZipResourceImageLoader` to a cost-bounded `NSCache` (purged on Settings window close) and rasterized the menu bar status item icon at `18×18` instead of retaining the full `512×512` source bitmap.
- **Real-Time Streaming Compression Progress & Engine Pre-Warming**: Added 512 KiB chunked progress reporting in `NativeZipEngine` and `-bsp1` live progress streaming in `SevenZipEngine` (forwarding configured `-mmt` thread counts and `-xr!.DS_Store/__MACOSX/._*` exclusions), plus background engine pre-warming off `@MainActor`.

---

## [0.1.3] - 2026-11-14

### Added
- **Finder Spacebar Toggle for ProZip Mini**: Added `FinderSpacebarMonitor` using macOS Accessibility & Automation (AppleEvents) permissions so pressing Spacebar in Finder on a supported archive opens ProZip Mini directly, and pressing Spacebar again inside Mini dismisses the window and returns focus to Finder—configurable with permission onboarding and scope toggles in Settings → ProZip Mini.
- **Password Book Keychain Authorization Recovery & Reset Fallback**: Preserves existing encrypted vaults when an open-source / ad-hoc re-signed binary invalidates legacy Keychain ACLs; added **Authorize & Recover Password Book** (prompts once via system Keychain UI, decrypts saved entries, and rotates onto a new key bound to the current app signature for silent future launches) alongside a two-step **Reset & Rebuild Password Book** fallback in Settings → Password Book and the protection dialog.

### Changed
- **Archive Size in ProZip Mini Header**: Updated the Mini window subtitle to display both item count and formatted archive file size.
- **Ad-Hoc Build Handling for Touch ID Quick Unlock**: Gracefully disables the Touch ID quick-unlock toggle in builds without an Apple Team ID while keeping the full Data Protection Keychain implementation intact for future signed commercial builds.
- **Interactive Demo GIF in README**: Added `Resources/ProZip-Demo.gif` showcasing UI modes and workflows.

### Fixed
- Fixed an issue where dragging the header, footer, or background area of the archive creation options sheet (`ArchiveCreationDialogView`) did not move the host window (`WindowDragArea.resolveRootWindow` parent-chain resolution + mouse drag tracking).
- Fixed Spacebar not dismissing the ProZip Mini window after launching via Finder Spacebar preview.

---

## [0.1.2] - 2026-11-12

### Added
- **GitHub Releases Auto-Update Service & UI Integration**: Introduced `AppUpdateService` to query the GitHub Releases API, perform semantic version comparison, display release note summaries, and open direct `.dmg` / `.zip` download links—integrated across the Check for Updates dialog, Settings → About pane, and 24-hour throttled silent launch checks.
- **Native macOS 26+ Liquid Glass Design System**: Built unified capsule, circular, and continuous-corner Liquid Glass modifiers powered by native `.glassEffect` and `GlassEffectContainer`, with graceful frosted-material fallbacks for macOS 14–15.

### Changed
- **Mini Window Optical Refraction & Interaction Polish**:
  - Calibrated Mini window Liquid Glass edge refraction, `20pt` continuous corner radius, and light/dark backdrop translucency, eliminating corner frame artifacts.
  - Upgraded the bottom-left circular controls (Close, Pin with sky-blue halo ring, Expand) and bottom-right `Preview + Extract All` capsule to native interactive Liquid Glass with smooth per-segment hover tinting and directional press lens response.
  - Made the Mini vertical scroller slot transparent and refined the bottom progressive fade mask.
- **Workspace & Welcome Window Liquid Glass Upgrade**:
  - Upgraded the top-right view-switcher capsule, Delete/Save/Search circular buttons (including active crimson Delete glass button and expanded search bar), breadcrumb navigation pill, and bottom-left action bar to native Liquid Glass.
  - Removed the static bottom white veil and redundant vertical dividers in Workspace mode so scrolled file rows refract directly through the floating Liquid Glass capsule.
  - Refined the primary Flow CTA's luminous glass rim and stacked peek card indicator, smoothly expanding the secondary `Extract` action on hover.
  - Unified the Welcome window's `Open Archive`, `Create Archive`, and `Settings` controls with native Liquid Glass.

### Fixed
- Fixed an issue where keyboard shortcut keycap badges (`⏎` / `Space`) inside the Workspace bottom action capsule turned white-on-white when hovered.

---

## [0.1.0] - 2026-11-12

### Added
- **Initial Open Source Release (GPL-3.0)**:
  - Four-tier archive engine architecture combining `NativeZipEngine` (zero-copy pure Swift ZIP reader), 7-Zip (multi-threaded LZMA2), system `libarchive`, and `hdiutil` disk image mounting.
  - High-speed hierarchical SQLite entry indexing (`EntryIndex`) for instant browsing and search across large archives.
  - Dual-mode workflow switching seamlessly (`⌥⌘M`) between the `1040×740` multi-view Workspace (Icons, List, Columns) and the `560×422` compact Mini browser.
  - Context-aware Flow recommendation engine (app bundle installation, font installation, safe allowlisted direct open, and one-click extraction).
  - Persistent menu bar Shelf for multi-source drag-and-drop staging, inline folder/archive browsing, and batch compression/extraction.
  - Local AES-GCM encrypted Password Book backed by macOS Keychain, Touch ID unlocking, and automatic password matching.
  - Bundled Finder context-menu extension (`ProZipFinderSync`) and Quick Look preview extension (`ProZipQuickLook`).

[0.1.5]: https://github.com/scoltzero/prozip/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/scoltzero/prozip/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/scoltzero/prozip/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/scoltzero/prozip/compare/v0.1.0...v0.1.2
[0.1.0]: https://github.com/scoltzero/prozip/releases/tag/v0.1.0
