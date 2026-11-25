# Мост заголовков системной библиотеки libarchive

[English](../../../../Sources/CArchive/README.md) · [简体中文](../../../zh-CN/Sources/CArchive/README.md) · [繁體中文](../../../zh-TW/Sources/CArchive/README.md) · [日本語](../../../ja/Sources/CArchive/README.md) · [한국어](../../../ko/Sources/CArchive/README.md) · [Español](../../../es/Sources/CArchive/README.md) · [Français](../../../fr/Sources/CArchive/README.md) · [Deutsch](../../../de/Sources/CArchive/README.md) · **Русский**

Этот таргет содержит только публичные заголовочные файлы. Он компонуется с системной библиотекой `libarchive` от Apple и не содержит, не собирает и не включает в бандл собственную реализацию `libarchive`, а также не использует Homebrew.

Публичные заголовки и оригинальный файл лицензии `COPYING` взяты без изменений из открытого дистрибутива Apple, тег `libarchive-167.120.3`, коммит `bd801c53e444038cf4bfed8318033e3b5cbce341`:

- https://github.com/apple-oss-distributions/libarchive/tree/bd801c53e444038cf4bfed8318033e3b5cbce341/libarchive
- `include/archive.h`: версия апстрима 3.7.4, SHA-256 `ef41e104bb8c2cbaaae8c5ad6a05290abb3bf552863d1bf76921be1b9009b3f2`
- `include/archive_entry.h`: SHA-256 `38820b6b4e85b4b8be02a397c5c2e2411bc772936a2c6e52ccb4ede85a3575a4`
- `include/COPYING`: SHA-256 `b2cdf763345de2de34cebf54394df3c61a105c3b71288603c251f2fa638200ba`

Уведомления о лицензии BSD полностью сохранены в заголовочных файлах и в `include/COPYING`.

В проверенном локально SDK Xcode macOS 27.0 эти заголовки отсутствуют, однако поставляются `usr/lib/libarchive.2.tbd` и символическая ссылка `libarchive.tbd`. Список экспортируемых символов включает колбэки чтения, колбэк позиционирования (seek), регистрацию форматов ZIP/TAR/7-Zip, `archive_read_data`, проверки зашифрованных записей и функции доступа к метаданным записей, используемые модулем предпросмотра. Локальная системная библиотека сообщает версию `libarchive 3.7.4`. Никакие более новые или неэкспортированные API не требуются.
