# 系统 libarchive 头文件桥接模块

[English](../../../../Sources/CArchive/README.md) · **简体中文** · [繁體中文](../../../zh-TW/Sources/CArchive/README.md) · [日本語](../../../ja/Sources/CArchive/README.md) · [한국어](../../../ko/Sources/CArchive/README.md) · [Español](../../../es/Sources/CArchive/README.md) · [Français](../../../fr/Sources/CArchive/README.md) · [Deutsch](../../../de/Sources/CArchive/README.md) · [Русский](../../../ru/Sources/CArchive/README.md)

本目标模块仅包含公开头文件，直接链接 Apple 系统内置的 `libarchive`，不包含、编译或打包独立的 `libarchive` 实现，也不依赖 Homebrew。

其中的公开头文件与原始 `COPYING` 许可证文件均未作修改，直接取自 Apple 开源发行仓库标签 `libarchive-167.120.3`（提交 `bd801c53e444038cf4bfed8318033e3b5cbce341`）：

- https://github.com/apple-oss-distributions/libarchive/tree/bd801c53e444038cf4bfed8318033e3b5cbce341/libarchive
- `include/archive.h`：上游版本 3.7.4，SHA-256 `ef41e104bb8c2cbaaae8c5ad6a05290abb3bf552863d1bf76921be1b9009b3f2`
- `include/archive_entry.h`：SHA-256 `38820b6b4e85b4b8be02a397c5c2e2411bc772936a2c6e52ccb4ede85a3575a4`
- `include/COPYING`：SHA-256 `b2cdf763345de2de34cebf54394df3c61a105c3b71288603c251f2fa638200ba`

原始 BSD 版权与许可声明完整保留于各头文件及 `include/COPYING` 中。

本地检查的 Xcode macOS 27.0 SDK 未附带上述头文件，但提供了 `usr/lib/libarchive.2.tbd` 及其符号链接 `libarchive.tbd`。其导出符号列表包含预览读取器所需的读取回调、寻址回调、ZIP/TAR/7-Zip 格式注册、`archive_read_data`、加密条目检测以及条目元数据访问接口。本地系统动态库报告版本为 `libarchive 3.7.4`，无需任何更新或未导出的私有 API。
