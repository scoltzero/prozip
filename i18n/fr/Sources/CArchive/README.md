# Pont d’en-têtes `libarchive` système

[English](../../../../Sources/CArchive/README.md) · [简体中文](../../../zh-CN/Sources/CArchive/README.md) · [繁體中文](../../../zh-TW/Sources/CArchive/README.md) · [日本語](../../../ja/Sources/CArchive/README.md) · [한국어](../../../ko/Sources/CArchive/README.md) · [Español](../../../es/Sources/CArchive/README.md) · **Français** · [Deutsch](../../../de/Sources/CArchive/README.md) · [Русский](../../../ru/Sources/CArchive/README.md)

Cette cible contient uniquement des en-têtes publics. Elle se lie à la bibliothèque `libarchive` système d’Apple et ne contient, ne compile ni n’embarque aucune implémentation propre de `libarchive`, sans recourir à Homebrew.

Les en-têtes publics et le fichier `COPYING` d’origine sont des fichiers non modifiés issus de la distribution open source d’Apple, tag `libarchive-167.120.3`, commit `bd801c53e444038cf4bfed8318033e3b5cbce341` :

- https://github.com/apple-oss-distributions/libarchive/tree/bd801c53e444038cf4bfed8318033e3b5cbce341/libarchive
- `include/archive.h` : version amont 3.7.4, SHA-256 `ef41e104bb8c2cbaaae8c5ad6a05290abb3bf552863d1bf76921be1b9009b3f2`
- `include/archive_entry.h` : SHA-256 `38820b6b4e85b4b8be02a397c5c2e2411bc772936a2c6e52ccb4ede85a3575a4`
- `include/COPYING` : SHA-256 `b2cdf763345de2de34cebf54394df3c61a105c3b71288603c251f2fa638200ba`

Les mentions de licence BSD d’origine demeurent intactes dans les en-têtes et dans `include/COPYING`.

Le SDK Xcode macOS 27.0 inspecté localement omet ces en-têtes, mais fournit `usr/lib/libarchive.2.tbd` ainsi que son lien symbolique `libarchive.tbd`. Sa liste d’exportation contient les rappels de lecture, le rappel de positionnement (*seek*), l’enregistrement des formats ZIP/TAR/7-Zip, `archive_read_data`, les vérifications d’entrées chiffrées et les accesseurs de métadonnées d’entrées utilisés par le lecteur d’aperçu. La bibliothèque système locale indique la version `libarchive 3.7.4`. Aucune API plus récente ou non exportée n’est requise.
