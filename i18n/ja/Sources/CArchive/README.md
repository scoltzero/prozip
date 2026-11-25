# システム libarchive ヘッダブリッジ

[English](../../../../Sources/CArchive/README.md) · [简体中文](../../../zh-CN/Sources/CArchive/README.md) · [繁體中文](../../../zh-TW/Sources/CArchive/README.md) · **日本語** · [한국어](../../../ko/Sources/CArchive/README.md) · [Español](../../../es/Sources/CArchive/README.md) · [Français](../../../fr/Sources/CArchive/README.md) · [Deutsch](../../../de/Sources/CArchive/README.md) · [Русский](../../../ru/Sources/CArchive/README.md)

このターゲットには公開ヘッダファイルのみが含まれています。Apple のシステム標準 `libarchive` にリンクするものであり、独自の `libarchive` 実装の同梱・ビルド・バンドルは行わず、Homebrew も使用しません。

公開ヘッダおよびオリジナルの `COPYING` は、Apple のオープンソース配布リポジトリ（タグ `libarchive-167.120.3`、コミット `bd801c53e444038cf4bfed8318033e3b5cbce341`）から無改変のまま取得したファイルです：

- https://github.com/apple-oss-distributions/libarchive/tree/bd801c53e444038cf4bfed8318033e3b5cbce341/libarchive
- `include/archive.h`：上流バージョン 3.7.4、SHA-256 `ef41e104bb8c2cbaaae8c5ad6a05290abb3bf552863d1bf76921be1b9009b3f2`
- `include/archive_entry.h`：SHA-256 `38820b6b4e85b4b8be02a397c5c2e2411bc772936a2c6e52ccb4ede85a3575a4`
- `include/COPYING`：SHA-256 `b2cdf763345de2de34cebf54394df3c61a105c3b71288603c251f2fa638200ba`

BSD ライセンス表記は各ヘッダおよび `include/COPYING` 内にそのまま保持されています。

ローカル環境で確認した Xcode macOS 27.0 SDK にはこれらのヘッダが含まれていませんが、`usr/lib/libarchive.2.tbd` とそのシンボリックリンク `libarchive.tbd` が同梱されています。そのエクスポート一覧には、プレビューリーダーが使用する読み取りコールバック、シークコールバック、ZIP/TAR/7-Zip フォーマット登録、`archive_read_data`、暗号化エントリ判定、およびエントリメタデータ取得関数が含まれています。ローカルのシステムライブラリは `libarchive 3.7.4` を報告しており、これより新しい API や未エクスポートの API は一切不要です。
