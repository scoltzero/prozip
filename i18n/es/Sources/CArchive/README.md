# Puente de cabeceras para `libarchive` del sistema

[English](../../../../Sources/CArchive/README.md) · [简体中文](../../../zh-CN/Sources/CArchive/README.md) · [繁體中文](../../../zh-TW/Sources/CArchive/README.md) · [日本語](../../../ja/Sources/CArchive/README.md) · [한국어](../../../ko/Sources/CArchive/README.md) · **Español** · [Français](../../../fr/Sources/CArchive/README.md) · [Deutsch](../../../de/Sources/CArchive/README.md) · [Русский](../../../ru/Sources/CArchive/README.md)

Este módulo de destino contiene únicamente cabeceras públicas. Enlaza con la biblioteca `libarchive` integrada en el sistema de Apple y no contiene, compila ni empaqueta una implementación propia de `libarchive`, ni depende de Homebrew.

Las cabeceras públicas y el archivo `COPYING` original son archivos sin modificar procedentes de la distribución de código abierto de Apple, etiqueta `libarchive-167.120.3`, commit `bd801c53e444038cf4bfed8318033e3b5cbce341`:

- https://github.com/apple-oss-distributions/libarchive/tree/bd801c53e444038cf4bfed8318033e3b5cbce341/libarchive
- `include/archive.h`: versión original 3.7.4, SHA-256 `ef41e104bb8c2cbaaae8c5ad6a05290abb3bf552863d1bf76921be1b9009b3f2`
- `include/archive_entry.h`: SHA-256 `38820b6b4e85b4b8be02a397c5c2e2411bc772936a2c6e52ccb4ede85a3575a4`
- `include/COPYING`: SHA-256 `b2cdf763345de2de34cebf54394df3c61a105c3b71288603c251f2fa638200ba`

Los avisos de licencia BSD originales se conservan íntegros en las cabeceras y en `include/COPYING`.

El SDK de Xcode macOS 27.0 inspeccionado localmente omite estas cabeceras, pero incluye `usr/lib/libarchive.2.tbd` y su enlace simbólico `libarchive.tbd`. Su lista de símbolos exportados contiene las retrollamadas de lectura, la retrollamada de posicionamiento (*seek*), el registro de formatos ZIP/TAR/7-Zip, `archive_read_data`, las comprobaciones de entradas cifradas y los accesores de metadatos de entradas utilizados por el lector de vista previa. La biblioteca local del sistema informa de la versión `libarchive 3.7.4`. No se requiere ninguna API más reciente ni no exportada.
