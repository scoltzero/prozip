# 시스템 libarchive 헤더 브리지

[English](../../../../Sources/CArchive/README.md) · [简体中文](../../../zh-CN/Sources/CArchive/README.md) · [繁體中文](../../../zh-TW/Sources/CArchive/README.md) · [日本語](../../../ja/Sources/CArchive/README.md) · **한국어** · [Español](../../../es/Sources/CArchive/README.md) · [Français](../../../fr/Sources/CArchive/README.md) · [Deutsch](../../../de/Sources/CArchive/README.md) · [Русский](../../../ru/Sources/CArchive/README.md)

이 타깃에는 공개 헤더 파일만 포함되어 있습니다. Apple의 시스템 기본 `libarchive`에 링크하며, 별도의 `libarchive` 구현을 포함·빌드·번들링하거나 Homebrew를 사용하지 않습니다.

공개 헤더와 원본 `COPYING` 파일은 Apple 오픈소스 배포판(태그 `libarchive-167.120.3`, 커밋 `bd801c53e444038cf4bfed8318033e3b5cbce341`)에서 수정 없이 그대로 가져온 파일입니다:

- https://github.com/apple-oss-distributions/libarchive/tree/bd801c53e444038cf4bfed8318033e3b5cbce341/libarchive
- `include/archive.h`: 업스트림 버전 3.7.4, SHA-256 `ef41e104bb8c2cbaaae8c5ad6a05290abb3bf552863d1bf76921be1b9009b3f2`
- `include/archive_entry.h`: SHA-256 `38820b6b4e85b4b8be02a397c5c2e2411bc772936a2c6e52ccb4ede85a3575a4`
- `include/COPYING`: SHA-256 `b2cdf763345de2de34cebf54394df3c61a105c3b71288603c251f2fa638200ba`

BSD 저작권 및 라이선스 고지문은 각 헤더와 `include/COPYING`에 그대로 유지되어 있습니다.

로컬에서 확인한 Xcode macOS 27.0 SDK에는 해당 헤더가 빠져 있지만, `usr/lib/libarchive.2.tbd`와 심볼릭 링크인 `libarchive.tbd`가 기본 제공됩니다. 내보내기(export) 심볼 목록에는 미리보기 리더가 사용하는 읽기 콜백, 탐색(seek) 콜백, ZIP/TAR/7-Zip 포맷 등록, `archive_read_data`, 암호화 항목 확인, 항목 메타데이터 접근자가 모두 포함되어 있습니다. 로컬 시스템 라이브러리는 `libarchive 3.7.4`로 보고되며, 더 새로운 API나 내보내지지 않은 비공개 API는 필요하지 않습니다.
