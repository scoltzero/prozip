# 변경 로그 (Changelog)

[English](../../CHANGELOG.md) · [简体中文](../zh-CN/CHANGELOG.md) · [繁體中文](../zh-TW/CHANGELOG.md) · [日本語](../ja/CHANGELOG.md) · **한국어** · [Español](../es/CHANGELOG.md) · [Français](../fr/CHANGELOG.md) · [Deutsch](../de/CHANGELOG.md) · [Русский](../ru/CHANGELOG.md)

**ProZip**의 모든 주요 변경 사항은 이 문서에 기록됩니다.

이 문서의 형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/)를 기반으로 하며, 본 프로젝트는 [유의적 버전(Semantic Versioning)](https://semver.org/lang/ko/)을 준수합니다.

---

## [0.1.5] - 2026-11-23

### 추가됨 (Added)
- **앱 내 자체 업데이트 (다운로드, 검증 및 자동 재실행)**:
  - 업데이트 확인 대화상자 안에 원클릭 **지금 업데이트** 버튼을 추가하여 브라우저에서 직접 다운로드하고 드래그 설치할 필요가 없도록 개선했습니다.
  - 실시간 진행률과 함께 GitHub Release `.zip`을 스트리밍 다운로드하고, `CryptoKit`으로 `SHA256SUMS.txt`를 검증하며 `CFBundleIdentifier`를 확인한 뒤, `/usr/bin/ditto`로 압축을 풀어 `ProZip.app`을 원자적으로 교체(실패 시 자동 롤백 및 필요 시 관리자 권한 프롬프트 표시)하고 자동으로 다시 실행합니다.

### 수정 및 변경됨 (Fixed & Changed)
- **단색 템플릿 메뉴 막대 아이콘 및 보관함 정렬 개선**:
  - 기존 컬러 메뉴 막대 아이콘을 브랜드 문자 **P**와 33% 불투명도 그림자만 남긴 해상도 독립적 macOS 템플릿 아이콘(`isTemplate = true`)으로 교체하여 라이트 모드와 다크 모드에 자동 적응하도록 개선했습니다.
  - 메뉴 막대 보관함 패널의 상단 여백을 줄이고 메뉴 막대 하단 가장자리에 밀착시켜 불필요한 간격을 없앴으며, 설정 화면의 미리보기와도 정렬을 일치시켰습니다.
- **실시간 압축 해제 진행률**: 분할 RAR을 포함한 모든 지원 아카이브 포맷에서 실시간 압축 해제 진행률을 스트리밍으로 표시합니다.

---

## [0.1.4] - 2026-11-21

### 추가됨 (Added)
- **Dock에 표시 / 가리기 환경설정**: 설정 → 일반 → 시작에 **Dock에 표시** 토글을 추가하여 활성 윈도우 포커스를 유지한 채 재시작 없이 실시간으로 `NSApplication.ActivationPolicy`(`.regular` / `.accessory`)를 전환할 수 있도록 했습니다. 또한 메뉴 막대 Box 우클릭 메뉴에 빠른 **설정…** 항목을 추가하고 중국어 간체, 중국어 번체, 영어 현지화를 반영했습니다.
- **세분화된 작업 대기열 정리 및 크기 조절 가능한 독립 생성 윈도우**:
  - `ArchiveProgressWindowView`에 개별 작업 닫기 버튼, **완료된 항목 지우기**(실패한 작업 포함), **모두 지우기** 동작을 추가했습니다.
  - `ArchiveCreationDialogView`를 이전 크기를 기억하는 크기 조절형 독립 윈도우로 호스팅하고, 요약 영역의 정리/호환성 행을 직접 클릭해 전환할 수 있는 토글로 개선했습니다.

### 변경됨 (Changed)
- **유휴 메모리 회수 및 백그라운드 CPU 깨움 제로화**:
  - `ProZipLandingView`의 헤드라인 회전 애니메이션을 `isWindowActive`에 연결하여 백그라운드 전환, 포커스 해제 또는 최소화 시 애니메이션 루프를 즉시 일시 정지하고 유휴 CPU 깨움을 0으로 줄였습니다.
  - 환영 윈도우, 설정 윈도우(기억된 크기는 유지), 메뉴 막대 보관함 패널, 작업 진행 패널, 알림 윈도우를 닫을 때 `NSHostingView` 계층과 백킹 버퍼를 해제하며, 활성 아카이브 세션이 이미 있을 때는 환영 윈도우를 미리 생성하지 않도록 개선했습니다.
  - `ProZipResourceImageLoader`를 비용 제한이 있는 `NSCache`(설정 윈도우를 닫을 때 비움)로 전환하고, 메뉴 막대 상태 아이콘을 전체 `512×512` 원본 비트맵 대신 `18×18` 크기로 래스터화하도록 변경했습니다.
- **실시간 스트리밍 압축 진행률 및 엔진 사전 예열**: `NativeZipEngine`에 512 KiB 청크 단위 진행률 보고를 추가하고 `SevenZipEngine`에 `-bsp1` 실시간 진행률 스트리밍(설정된 `-mmt` 스레드 수 및 `-xr!.DS_Store/__MACOSX/._*` 제외 규칙 전달)을 도입했으며, `@MainActor` 외부에서 수행되는 백그라운드 엔진 사전 예열을 추가했습니다.

---

## [0.1.3] - 2026-11-14

### 추가됨 (Added)
- **Finder 스페이스바를 통한 ProZip Mini 토글**: macOS 손쉬운 사용(Accessibility) 및 자동화(AppleEvents) 권한을 활용하는 `FinderSpacebarMonitor`를 추가하여 Finder에서 지원 아카이브를 선택하고 스페이스바를 누르면 ProZip Mini가 바로 열리고, Mini 내부에서 다시 스페이스바를 누르면 창을 닫고 Finder로 포커스를 되돌립니다(설정 → ProZip Mini에서 권한 온보딩 및 적용 범위 토글 제공).
- **암호 보관소 키체인 인증 복구 및 재설정 폴백**: 오픈소스 / 애드혹(ad-hoc) 재서명 바이너리로 인해 기존 키체인 ACL이 무효화되더라도 암호화된 기존 보관소를 보존하며, 시스템 키체인 UI를 통해 한 번 인증하여 저장된 항목을 복호화하고 현재 앱 서명에 바인딩된 새 키로 교체해 이후 무음 실행을 복원하는 **암호 보관소 인증 및 복구**와 2단계 확인 방식의 **암호 보관소 재설정 및 다시 만들기** 폴백을 설정 → 암호 보관소 및 보호 대화상자에 추가했습니다.

### 변경됨 (Changed)
- **ProZip Mini 헤더에 아카이브 크기 표시**: Mini 윈도우 부제목에 항목 개수와 포맷팅된 아카이브 파일 크기를 함께 표시하도록 업데이트했습니다.
- **Touch ID 빠른 잠금 해제의 애드혹 빌드 처리**: Apple Team ID가 없는 빌드에서는 Touch ID 빠른 잠금 해제 토글을 자연스럽게 비활성화하는 한편, 향후 서명된 상용 빌드를 위해 전체 Data Protection Keychain 구현은 그대로 유지했습니다.
- **README 인터랙티브 데모 GIF 추가**: [README.md](README.md)에 UI 모드와 워크플로를 보여주는 `Resources/ProZip-Demo.gif`를 추가했습니다.

### 수정됨 (Fixed)
- 아카이브 생성 옵션 시트(`ArchiveCreationDialogView`)의 헤더, 푸터 또는 빈 배경 영역을 드래그해도 호스트 윈도우가 이동하지 않던 문제를 수정했습니다(`WindowDragArea.resolveRootWindow` 부모 체인 탐색 + 마우스 드래그 추적).
- Finder 스페이스바 미리보기로 실행한 뒤 스페이스바를 눌러도 ProZip Mini 윈도우가 닫히지 않던 문제를 수정했습니다.

---

## [0.1.2] - 2026-11-12

### 추가됨 (Added)
- **GitHub Releases 자동 업데이트 서비스 및 UI 통합**: GitHub Releases API를 조회해 유의적 버전을 비교하고, 릴리스 노트 요약을 표시하며, `.dmg` / `.zip` 직접 다운로드 링크를 여는 `AppUpdateService`를 도입하여 업데이트 확인 대화상자, 설정 → 정보 패널, 그리고 24시간 주기로 제한되는 시작 시 무음 확인에 통합했습니다.
- **네이티브 macOS 26+ Liquid Glass 디자인 시스템**: 네이티브 `.glassEffect` 및 `GlassEffectContainer` 기반의 통합 캡슐형, 원형, 연속 곡률 코너 Liquid Glass 모디파이어를 구축하고 macOS 14–15용 반투명 머티리얼 폴백을 제공했습니다.

### 변경됨 (Changed)
- **Mini 윈도우 광학 굴절 및 인터랙션 다듬기**:
  - Mini 윈도우의 Liquid Glass 가장자리 굴절, `20pt` 연속 모서리 반경, 라이트/다크 배경 투과도를 보정하여 모서리 프레임 아티팩트를 제거했습니다.
  - 좌측 하단 원형 컨트롤(닫기, 스카이블루 후광 링이 있는 고정, 확장)과 우측 하단 `미리보기 + 전체 압축 해제` 캡슐을 네이티브 인터랙티브 Liquid Glass로 업그레이드하여 세그먼트별 부드러운 호버 틴팅과 방향성 프레스 렌즈 반응을 구현했습니다.
  - Mini 세로 스크롤바 슬롯을 투명화하고 하단 점진적 페이드 마스크를 정교화했습니다.
- **Workspace 및 환영 윈도우 Liquid Glass 업그레이드**:
  - 우측 상단 보기 전환 캡슐, 삭제/저장/검색 원형 버튼(활성 크림슨 삭제 유리 버튼 및 확장형 검색 막대 포함), 경로 이동 브레드크럼 필, 좌측 하단 작업 막대를 네이티브 Liquid Glass로 업그레이드했습니다.
  - Workspace 모드의 정적 하단 흰색 베일과 불필요한 세로 구분선을 제거하여 스크롤되는 파일 행이 플로팅 Liquid Glass 캡슐 너머로 직접 굴절되어 보이도록 개선했습니다.
  - 기본 Flow CTA의 발광 유리 테두리와 겹쳐진 피크 카드 인디케이터를 다듬어 호버 시 보조 `압축 해제` 동작이 부드럽게 펼쳐지도록 했습니다.
  - 환영 윈도우의 `아카이브 열기`, `아카이브 생성`, `설정` 컨트롤을 네이티브 Liquid Glass로 통일했습니다.

### 수정됨 (Fixed)
- Workspace 하단 작업 캡슐 내부의 키보드 단축키 키캡 배지(`⏎` / `Space`)가 호버 시 흰 배경에 흰 글씨로 변해 보이지 않던 문제를 수정했습니다.

---

## [0.1.0] - 2026-11-12

### 추가됨 (Added)
- **최초 오픈소스 릴리스 (GPL-3.0)**:
  - `NativeZipEngine`(제로카피 순수 Swift ZIP 리더), 7-Zip(멀티스레드 LZMA2), 시스템 `libarchive`, `hdiutil` 디스크 이미지 마운트를 결합한 4계층 아카이브 엔진 아키텍처.
  - 대규모 아카이브에서도 즉각적인 탐색과 검색을 지원하는 고속 계층형 SQLite 항목 인덱싱(`EntryIndex`).
  - `1040×740` 다중 보기 Workspace(아이콘, 목록, 계층)와 `560×422` 컴팩트 Mini 브라우저를 매끄럽게 오가는 듀얼 모드 워크플로(`⌥⌘M`).
  - 컨텍스트 인식 Flow 추천 엔진(앱 번들 설치, 서체 설치, 안전한 허용 목록 기반 직접 열기, 원클릭 압축 해제).
  - 다중 소스 드래그 앤 드롭 스테이징, 인라인 폴더/아카이브 탐색, 일괄 압축/압축 해제를 지원하는 상주형 메뉴 막대 보관함(Shelf).
  - macOS 키체인, Touch ID 잠금 해제, 자동 암호 매칭을 지원하는 로컬 AES-GCM 암호화 암호 보관소.
  - 번들 제공 Finder 컨텍스트 메뉴 확장 프로그램(`ProZipFinderSync`) 및 훑어보기 미리보기 확장 프로그램(`ProZipQuickLook`).

[0.1.5]: https://github.com/scoltzero/prozip/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/scoltzero/prozip/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/scoltzero/prozip/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/scoltzero/prozip/compare/v0.1.0...v0.1.2
[0.1.0]: https://github.com/scoltzero/prozip/releases/tag/v0.1.0
