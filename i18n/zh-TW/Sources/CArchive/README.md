# 系統 libarchive 標頭檔橋接模組

[English](../../../../Sources/CArchive/README.md) · [简体中文](../../../zh-CN/Sources/CArchive/README.md) · **繁體中文** · [日本語](../../../ja/Sources/CArchive/README.md) · [한국어](../../../ko/Sources/CArchive/README.md) · [Español](../../../es/Sources/CArchive/README.md) · [Français](../../../fr/Sources/CArchive/README.md) · [Deutsch](../../../de/Sources/CArchive/README.md) · [Русский](../../../ru/Sources/CArchive/README.md)

本目標模組僅包含公開標頭檔，直接連結 Apple 系統內建的 `libarchive`，不包含、編譯或封裝獨立的 `libarchive` 實作，亦不依賴 Homebrew。

其中的公開標頭檔與原始 `COPYING` 授權檔案均未經修改，直接取自 Apple 開源發行儲存庫標籤 `libarchive-167.120.3`（提交 `bd801c53e444038cf4bfed8318033e3b5cbce341`）：

- https://github.com/apple-oss-distributions/libarchive/tree/bd801c53e444038cf4bfed8318033e3b5cbce341/libarchive
- `include/archive.h`：上游版本 3.7.4，SHA-256 `ef41e104bb8c2cbaaae8c5ad6a05290abb3bf552863d1bf76921be1b9009b3f2`
- `include/archive_entry.h`：SHA-256 `38820b6b4e85b4b8be02a397c5c2e2411bc772936a2c6e52ccb4ede85a3575a4`
- `include/COPYING`：SHA-256 `b2cdf763345de2de34cebf54394df3c61a105c3b71288603c251f2fa638200ba`

原始 BSD 版權與授權聲明完整保留於各標頭檔及 `include/COPYING` 中。

本機檢查的 Xcode macOS 27.0 SDK 未附帶上述標頭檔，但提供了 `usr/lib/libarchive.2.tbd` 及其符號連結 `libarchive.tbd`。其匯出符號清單包含預覽讀取器所需的讀取回呼、尋址回呼、ZIP/TAR/7-Zip 格式註冊、`archive_read_data`、加密項目偵測以及項目中繼資料存取介面。本機系統動態函式庫回報版本為 `libarchive 3.7.4`，無需任何較新或未匯出的私有 API。
