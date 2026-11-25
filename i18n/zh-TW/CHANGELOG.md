# 更新日誌

[English](../../CHANGELOG.md) · [简体中文](../zh-CN/CHANGELOG.md) · **繁體中文** · [日本語](../ja/CHANGELOG.md) · [한국어](../ko/CHANGELOG.md) · [Español](../es/CHANGELOG.md) · [Français](../fr/CHANGELOG.md) · [Deutsch](../de/CHANGELOG.md) · [Русский](../ru/CHANGELOG.md)

本專案（**ProZip**）的所有重要變更均記錄於此檔案中。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/) 規範，版本號遵循 [語意化版本 (SemVer)](https://semver.org/lang/zh-TW/)。

---

## [0.1.5] - 2026-11-23

### 新增 (Added)
- **應用程式內一鍵更新（下載、驗證並自動重新啟動）**：
  - 在檢查更新對話框中新增「立即更新」功能，無需跳轉瀏覽器手動下載映像檔。
  - 直接在應用程式內串流下載 GitHub Release 中的 `.zip` 安裝檔並即時顯示下載進度，自動驗證 `SHA256SUMS.txt` 雜湊值與 `CFBundleIdentifier`，透過系統 `ditto` 解壓縮並原子替換目前 `ProZip.app`（失敗自動回滾備份，目錄無寫入權限時喚起系統授權視窗）後自動重新啟動新版。

### 修復與最佳化 (Fixed & Changed)
- **選單列黑白模板圖示與彈出面板貼齊間距修復**：
  - 將狀態列圖示改為基於品牌向量路徑繪製的 macOS 黑白模板圖示（`isTemplate = true`），移除綠色底色，僅保留主體 **P** 與 33% 透明度折影，自動適配淺色／深色模式及 Retina 解析度。
  - 收緊選單列檔案盒面板頂部內邊距並錨定選單列下緣，消除彈出視窗與選單列之間的多餘空隙，同步對齊設定頁外觀預覽。
- **全格式與分割 RAR 即時解壓縮進度**：修復分割 RAR 及其他壓縮檔格式解壓縮時進度條更新不即時的問題，實現全格式即時串流進度回報。

---

## [0.1.4] - 2026-11-21

### 新增 (Added)
- **Dock 圖示顯示／隱藏設定**：在「設定 → 一般 → 啟動」中新增 **「在 Dock 中顯示」** 開關，支援無需重新啟動即時切換 Dock 圖示顯示與隱藏（動態調整 `NSApplication.ActivationPolicy` 並維持目前作用中視窗焦點）；同時在選單列檔案盒右鍵選單中補充 **「設定…」** 快捷入口，同步提供簡中、繁中、英文三語介面文案。
- **工作佇列精細清理與獨立可縮放建立視窗**：
  - 壓縮工作佇列視窗（`ArchiveProgressWindowView`）新增單筆工作移除按鈕、一鍵「清除已完成」（包含失敗項目）與「全部清除」能力。
  - 建立壓縮檔設定面板（`ArchiveCreationDialogView`）升級為獨立可自由調整尺寸的視窗並自動記憶視窗大小；概覽卡片中的輔助檔案過濾與檔名相容列支援直接點擊切換。

### 變更與最佳化 (Changed)
- **閒置記憶體回收與背景零喚醒最佳化**：
  - 將歡迎頁（`ProZipLandingView`）標題輪播綁定至視窗作用中狀態，應用程式切入背景、失焦或最小化時立即停止定時動畫循環，消除背景待機 CPU 喚醒與堆積記憶體碎片。
  - 關閉或收起歡迎視窗、設定視窗（保留視窗尺寸記憶）、選單列檔案盒面板、工作進度視窗及提示視窗時主動卸載 `NSHostingView` 視圖樹並釋放圖層緩衝；已有作用中壓縮檔工作階段時不再於背景預先建立歡迎視窗。
  - 將內建資源圖片載入器（`ProZipResourceImageLoader`）改為具容量上限的 `NSCache`，設定視窗關閉時主動清理快取；選單列狀態圖示按 `18×18` 尺寸點陣化繪製，避免常駐持有高解析度原圖點陣圖。
- **即時串流壓縮進度與引擎預熱**：`NativeZipEngine` 支援 512 KiB 分塊串流進度回報，`SevenZipEngine` 接入 `-bsp1` 即時壓縮進度串流並傳遞 `-mmt` 執行緒數與 macOS 中繼資料排除規則（`-xr!.DS_Store/__MACOSX/._*`）；啟動時於背景低優先順序預熱壓縮引擎並將壓縮執行移出 `@MainActor`。

---

## [0.1.3] - 2026-11-14

### 新增 (Added)
- **Finder 空白鍵一鍵喚出／關閉 ProZip Mini**：基於系統輔助使用（Accessibility）與自動化（AppleEvents）授權的 `FinderSpacebarMonitor`，在 Finder 中選取支援的壓縮檔按空白鍵即可直接開啟 ProZip Mini 輕量視窗預覽；在 Mini 視窗聚焦時再次按下空白鍵即可關閉視窗並切回 Finder，支援在「設定 → ProZip Mini」中設定權限引導與接管格式範圍。
- **密碼本鑰匙圈授權復原與重置備援**：針對開源／自簽章版本更新或重簽後系統鑰匙圈 ACL 變更導致原有密碼本無法靜默解密的問題，保留加密檔案並在「設定 → 密碼本」及保護設定視窗提供 **「授權復原密碼本」**（一次性視窗授權後自動輪換並綁定新簽章金鑰，後續恢復靜默存取）與兩階段確認 **「清除並重建密碼本…」** 備援入口。

### 變更與最佳化 (Changed)
- **Mini 視窗標題列顯示檔案大小**：在 ProZip Mini 標題列副標題中同步顯示目前壓縮檔的項目數量與總檔案大小。
- **Touch ID 快速解鎖簽章環境適配**：在未設定商業開發者 Team ID 的開源／自簽章建置中溫和停用 Touch ID 快速解鎖勾選並提示原因，同時保留完整的 Data Protection Keychain 後端程式碼供後續開發者簽章建置使用。
- **專案文件展示動圖**：在 [README.md](README.md) 中新增互動介面與功能展示 GIF（`Resources/ProZip-Demo.gif`）。

### 修復 (Fixed)
- 修復建立壓縮檔選項視窗（`ArchiveCreationDialogView`）頂部標題列、底部工具列及空白背景區域無法拖曳移動整個視窗的問題（`WindowDragArea.resolveRootWindow` 沿父視窗鏈向上定位宿主視窗並結合事件追蹤拖曳）。
- 修復透過 Finder 空白鍵開啟 ProZip Mini 後，再次按下空白鍵未能關閉 Mini 視窗的問題。

---

## [0.1.2] - 2026-11-12

### 新增 (Added)
- **GitHub Releases 自動更新偵測與介面整合**：新增 `AppUpdateService` 模組，支援連接 GitHub Releases API 自動進行語意化版本比對、顯示更新說明摘要，並直接跳轉下載最新 `.dmg` / `.zip` 安裝檔；同步整合至「檢查更新」視窗、「設定 → 關於」頁面與啟動自動靜默檢查（24 小時節流）。
- **macOS 26+ 原生液態玻璃（Liquid Glass）視覺體系**：基於系統原生 `.glassEffect` 與 `GlassEffectContainer` 打造統一的膠囊、圓形及圓角矩形液態玻璃元件，同時保留 macOS 14–15 的毛玻璃平滑降級相容。

### 變更與最佳化 (Changed)
- **Mini 瀏覽視窗光學折射與互動精調**：
  - 校準 Mini 視窗表面原生液態玻璃折射邊緣、視窗圓角（`20pt`）與淺／深色桌面背景下的透光度，消除視窗四角灰色邊緣偽影。
  - 升級左下角關閉、置頂（含天藍外圈光環）、展開三個圓形控制鈕及右下角「預覽 + 全部解壓縮」膠囊為原生互動式液態玻璃，統一滑鼠懸停局部柔和染色與按壓液態透鏡擴張動效。
  - 透明化 Mini 列表右側捲軸軌道並最佳化底部漸層遮罩。
- **完整工作區（Workspace）與歡迎頁玻璃控制項升級**：
  - 升級右上角檢視模式切換膠囊、刪除／儲存／搜尋按鈕（含選取態緋紅刪除玻璃圓鈕與展開搜尋欄）、路徑導覽麵包屑膠囊及左下角操作列為原生液態玻璃。
  - 移除主視窗底部靜態白色遮罩與操作列內多餘垂直分隔線，使底層捲動檔案列可直接透過懸浮液態玻璃膠囊即時模糊折射。
  - 最佳化底部智慧 Flow 主按鈕邊緣玻璃高光與頂部疊層備選膠囊微露視覺，懸停時平滑展開備選「解壓縮」動作。
  - 歡迎視窗「開啟壓縮檔」、「建立壓縮檔」及「設定」按鈕同步切換為原生液態玻璃。

### 修復 (Fixed)
- 修復工作區左下角操作膠囊在滑鼠懸停時快速鍵徽章（`⏎` / `空白鍵`）因白底白字導致文字不可見的問題。

---

## [0.1.0] - 2026-11-12

### 新增 (Added)
- **首個開源版本發佈（GPL-3.0）**：
  - 四層協同解壓縮引擎架構：`NativeZipEngine`（純 Swift 零拷貝直讀）、7-Zip（LZMA2 多執行緒）、系統 `libarchive` 與 `hdiutil` 磁碟映像掛載。
  - 基於 SQLite 的階層式極速項目索引（`EntryIndex`），支援大型壓縮檔秒級目錄瀏覽與檢索。
  - `1040×740` 三種檢視完整工作區（圖示、列表、直欄）與 `560×422` 輕量 Mini 視窗雙模式無縫切換（`⌥⌘M`）。
  - 智慧 Flow 情境動作推薦引擎（應用程式安裝、字型安裝、白名單檔案安全直開與一鍵解壓縮）。
  - 常駐選單列檔案暫存盒（Shelf），支援多來源拖放收集、目錄內嵌穿透瀏覽與批次封存處理。
  - 本機 AES-GCM 安全密碼本，支援系統 Keychain 與 Touch ID 解鎖及多密碼自動比對解密。
  - 隨附 Finder 右鍵延伸功能（`ProZipFinderSync`）與空白鍵快速預覽外掛程式（`ProZipQuickLook`）。

[0.1.5]: https://github.com/scoltzero/prozip/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/scoltzero/prozip/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/scoltzero/prozip/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/scoltzero/prozip/compare/v0.1.0...v0.1.2
[0.1.0]: https://github.com/scoltzero/prozip/releases/tag/v0.1.0
