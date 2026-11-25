# Header-Brücke für das System-`libarchive`

[English](../../../../Sources/CArchive/README.md) · [简体中文](../../../zh-CN/Sources/CArchive/README.md) · [繁體中文](../../../zh-TW/Sources/CArchive/README.md) · [日本語](../../../ja/Sources/CArchive/README.md) · [한국어](../../../ko/Sources/CArchive/README.md) · [Español](../../../es/Sources/CArchive/README.md) · [Français](../../../fr/Sources/CArchive/README.md) · **Deutsch** · [Русский](../../../ru/Sources/CArchive/README.md)

Dieses Target enthält ausschließlich öffentliche Header-Dateien. Es linkt gegen Apples systemeigenes `libarchive` und enthält, kompiliert oder bündelt weder eine eigene `libarchive`-Implementierung noch verwendet es Homebrew.

Die öffentlichen Header und die ursprüngliche `COPYING`-Datei stammen unverändert aus Apples Open-Source-Distribution, Tag `libarchive-167.120.3`, Commit `bd801c53e444038cf4bfed8318033e3b5cbce341`:

- https://github.com/apple-oss-distributions/libarchive/tree/bd801c53e444038cf4bfed8318033e3b5cbce341/libarchive
- `include/archive.h`: Upstream-Version 3.7.4, SHA-256 `ef41e104bb8c2cbaaae8c5ad6a05290abb3bf552863d1bf76921be1b9009b3f2`
- `include/archive_entry.h`: SHA-256 `38820b6b4e85b4b8be02a397c5c2e2411bc772936a2c6e52ccb4ede85a3575a4`
- `include/COPYING`: SHA-256 `b2cdf763345de2de34cebf54394df3c61a105c3b71288603c251f2fa638200ba`

Die ursprünglichen BSD-Lizenzhinweise bleiben in den Headern und in `include/COPYING` unverändert erhalten.

Das lokal geprüfte Xcode macOS 27.0 SDK lässt diese Header weg, liefert jedoch `usr/lib/libarchive.2.tbd` sowie dessen Symlink `libarchive.tbd` mit. Dessen Exportliste umfasst die Lese-Callbacks, den Seek-Callback, die Formatregistrierung für ZIP/TAR/7-Zip, `archive_read_data`, Prüfungen auf verschlüsselte Einträge sowie die vom Vorschau-Reader genutzten Metadaten-Zugriffsfunktionen. Die lokale Systembibliothek meldet `libarchive 3.7.4`. Es wird keine neuere oder nicht exportierte API benötigt.
