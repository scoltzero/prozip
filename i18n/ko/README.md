<p align="center">
  <img src="../../Resources/AppIcon-Preview.png" alt="ProZip Logo" width="160">
</p>

<h1 align="center">ProZip</h1>

<p align="center">
  <strong>모던하고 우아하며 강력한 macOS용 고성능 오픈소스 아카이브 관리자</strong><br>
  네이티브 Swift &amp; SwiftUI 제작 · 4계층 엔진 파이프라인 · 초고속 SQLite 인덱싱 · 깊은 시스템 확장 통합
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="../zh-CN/README.md">简体中文</a> ·
  <a href="../zh-TW/README.md">繁體中文</a> ·
  <a href="../ja/README.md">日本語</a> ·
  <strong>한국어</strong> ·
  <a href="../es/README.md">Español</a> ·
  <a href="../fr/README.md">Français</a> ·
  <a href="../de/README.md">Deutsch</a> ·
  <a href="../ru/README.md">Русский</a>
</p>

<p align="center">
  <a href="https://github.com/scoltzero/prozip/stargazers"><img src="https://img.shields.io/github/stars/scoltzero/prozip?style=flat-square&logo=github&label=Stars" alt="GitHub Stars"></a>
  <a href="https://github.com/scoltzero/prozip/forks"><img src="https://img.shields.io/github/forks/scoltzero/prozip?style=flat-square&logo=github&label=Forks" alt="GitHub Forks"></a>
  <a href="https://github.com/scoltzero/prozip/releases"><img src="https://img.shields.io/github/downloads/scoltzero/prozip/total?style=flat-square&label=Downloads" alt="GitHub Downloads"></a>
  <a href="https://github.com/scoltzero/prozip/releases/latest"><img src="https://img.shields.io/github/v/release/scoltzero/prozip?style=flat-square&label=Release" alt="Latest Release"></a>
  <a href="https://developer.apple.com/macos/"><img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="Platform macOS 14+"></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/github/license/scoltzero/prozip?style=flat-square&label=License" alt="License"></a>
</p>

<p align="center">
  <a href="https://github.com/scoltzero/prozip/releases/latest"><img src="https://img.shields.io/badge/Download-Latest%20Release-0969DA?style=for-the-badge&logo=github&logoColor=white" alt="최신 릴리스 다운로드"></a>
  <a href="#빠른-시작"><img src="https://img.shields.io/badge/Guide-Quick%20Start-334155?style=for-the-badge&logo=readthedocs&logoColor=white" alt="빠른 시작"></a>
  <a href="https://github.com/scoltzero/prozip/issues"><img src="https://img.shields.io/badge/Feedback-Issues-2EA44F?style=for-the-badge&logo=github&logoColor=white" alt="피드백 및 이슈"></a>
</p>

<p align="center">
  <img src="../../Resources/ProZip-Demo.gif" alt="ProZip UI 및 주요 기능 데모" width="920">
</p>

> [!IMPORTANT]
> **프로젝트 지향점 및 목적**:
> ProZip은 모던 macOS 데스크톱 아키텍처, SwiftUI + AppKit 하이브리드 인터랙션 설계, 다중 엔진 아카이브 스트리밍 파이프라인, 그리고 클린룸(Clean-Room) 소프트웨어 엔지니어링의 학습·연구·기술 탐구를 위해 독립적으로 개발된 완전 오픈소스 프로젝트입니다.
>
> 본 소프트웨어는 기술 교류 및 교육 목적으로만 제공되며, 시중의 어떠한 상용 압축 프로그램과도 경쟁하려는 의도가 없습니다. 모든 코드는 역컴파일된 상용 소스 코드나 비인가 에셋 없이 처음부터 직접 작성되었으며, [GNU General Public License v3.0](../../LICENSE) 라이선스에 따라 공개됩니다. macOS 개발자와 오픈소스 기여자 여러분의 탐구, 토론 및 개선 참여를 진심으로 환영합니다.

---

## 왜 ProZip인가요?

| 핵심 기능 | 설명 |
|---|---|
| **네이티브 성능과 완성도** | 순수 Swift와 SwiftUI로 제작되어 macOS 고유의 시각적 계층 구조, Liquid Glass 광학 질감, 기민한 촉각적 반응성을 제공합니다. |
| **4계층 엔진 시너지** | `NativeZipEngine`(제로카피 직접 리더), 7-Zip(멀티스레드 LZMA2), 시스템 `libarchive`, 그리고 `hdiutil` 디스크 이미지 마운트를 하나로 결합했습니다. |
| **초고속 이중 테이블 SQLite 인덱싱** | 아카이브를 여는 즉시 로컬 계층형 인덱스 DB를 구축하여 수만 개의 항목도 밀리초 단위로 펼치고, 필터링하고, 선택 압축 해제할 수 있습니다. |
| **유연한 듀얼 모드 워크스페이스** | 모든 기능을 갖춘 `1040×740` 다중 컬럼 Workspace와 컴팩트한 `560×422` 반투명 Mini 브라우저 사이를 매끄럽게 전환합니다(`⌥⌘M`). |
| **스마트 컨텍스트 인식 Flow** | 아카이브 내부 콘텐츠(앱, 서체, 문서 등)를 자동으로 분석하여 **응용 프로그램에 설치**, **서체 설치**, 바로 열기 등 맥락에 맞는 동작을 추천합니다. |
| **메뉴 막대 임시 보관함 (ProZip Box)** | 메뉴 막대에 상주하는 드롭 존으로, 여러 폴더의 파일을 모아 두고 디렉터리를 인라인으로 탐색하며 원클릭 일괄 압축을 수행할 수 있습니다. |
| **안전한 암호 보관소 및 Touch ID** | macOS 키체인과 Touch ID로 보호되는 로컬 AES-GCM 암호화 보관소를 제공하며, 아카이브 잠금 해제 시 저장된 암호를 자동으로 순회 매칭합니다. |
| **깊은 시스템 확장 통합** | Finder 컨텍스트 메뉴 확장 프로그램(`FinderSync`)과 스페이스바 훑어보기(`Quick Look`) 즉시 미리보기 플러그인을 기본 탑재했습니다. |

---

## 포맷 지원 매트릭스

| 구분 | 지원 포맷 및 기능 |
|---|---|
| **압축 해제 및 탐색** | ZIP, 7Z, RAR (v4 / v5 / 분할 압축), TAR, GZ, TGZ, BZ2, TBZ2, XZ, TXZ, ZST, TZST, CPIO, CAB, ISO, DMG 등 |
| **아카이브 생성** | ZIP (Deflate 압축 레벨 조절, AES-256 암호화, 분할 볼륨), 7Z (고압축률 LZMA2, 헤더 암호화, 분할 볼륨), TAR |
| **제자리 편집 및 저장** | 원자적 커밋 트랜잭션과 자동 롤백 보호를 통해 기존 단일 볼륨 아카이브 내부에서 직접 항목 추가, 삭제, 이름 변경 지원 |

---

## 시스템 요구 사항

- **운영체제**: macOS 14.0 (Sonoma) 이상
- **아키텍처**: Apple Silicon(M 시리즈) 네이티브 및 Intel(`x86_64`) 호환
- **개인정보 및 실행 환경**: 100% 로컬 오프라인 실행 — 기본적으로 어떠한 네트워크 추적, 텔레메트리, 원격 분석도 수행하지 않음

---

## 빠른 시작

### 1. 사전 빌드된 릴리스 다운로드
[Latest Release](https://github.com/scoltzero/prozip/releases/latest) 페이지에서 `ProZip-v0.1.5-macos.dmg` 또는 `ProZip-v0.1.5-macos.zip`을 다운로드합니다(릴리스 노트는 [CHANGELOG.md](CHANGELOG.md) 참고).

### 2. 설치 및 실행
1. `.dmg` 디스크 이미지를 열고 `ProZip.app`을 `Applications`(응용 프로그램) 폴더로 드래그합니다.
2. ProZip을 더블 클릭하여 실행합니다. macOS에서 확인되지 않은 개발자 안내가 표시되면 **시스템 설정 → 개인정보 보호 및 보안**으로 이동한 뒤 **그래도 열기**를 클릭합니다.
3. 첫 실행 온보딩 마법사의 안내에 따라 필요에 맞게 Finder 확장 프로그램과 훑어보기(Quick Look) 미리보기 플러그인을 활성화합니다.

---

## 아키텍처

ProZip은 UI 표현, 세션 상태, 항목 인덱싱, 저수준 아카이브 엔진을 깔끔하게 분리한 계층형 아키텍처를 채택하고 있습니다:

```text
┌─────────────────────────────────────────────────────────────┐
│              ProZip App & Extensions Layer                  │
│   (WorkspaceWindowView / MiniWindowView / MenuBarShelf)     │
│   (ProZipFinderSync Extension / ProZipQuickLook Plugin)     │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    ProZipUI & ViewModels                    │
│   - AppViewModel (세션 조율, 상태 전환 및 Flow 동작 결정)   │
│   - ProZipTheme (네이티브 스타일, 색상 계층 및 모션 효과)   │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    ProZipCore Engine Layer                  │
│   - ArchiveBrowsingSession (세션 수명 주기 및 스테이징)     │
│   - EntryIndex (고속 SQLite 디렉터리 및 항목 인덱스)        │
│   - PasswordBook (AES-GCM + 키체인 + Touch ID 암호 보관소)  │
│   - ManagedTemporaryArtifactRegistry (임시 파일 수명 관리)  │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                   Archive Engine Broker                     │
│   ├─ NativeZipEngine   : 순수 Swift 직접 읽기 및 고속 쓰기  │
│   ├─ SevenZipEngine    : 7-Zip LZMA2 / AES / 다중 포맷 지원 │
│   ├─ LibarchiveEngine  : 시스템 libarchive 스트리밍 계층    │
│   └─ DiskImageEngine   : hdiutil 디스크 이미지 마운트       │
└─────────────────────────────────────────────────────────────┘
```

---

## 소스에서 빌드하기

ProZip은 Swift Package Manager로 관리되며 자동화된 패키징 스크립트를 포함합니다:

### 사전 준비 사항
- macOS 14.0 이상 및 Xcode 15 이상(또는 Xcode Command Line Tools) 설치
- Homebrew로 설치한 `7zz` (내장 7-Zip 엔진 서브셋 번들링에 사용):
  ```bash
  brew install sevenzip
  ```

### 빌드 단계
1. **저장소 클론**:
   ```bash
   git clone https://github.com/scoltzero/prozip.git
   cd prozip
   ```

2. **핵심 Swift 모듈 컴파일**:
   ```bash
   swift build -c release
   ```

3. **전체 macOS `.app` 번들 패키징** (Finder 확장 프로그램 및 훑어보기 확장 포함):
   ```bash
   bash scripts/build_app.sh release
   ```
   완료되면 패키징된 앱 번들이 `build/ProZip.app`에 생성됩니다.

---

## 독립 구현 및 오픈소스 성명

<details>
<summary><strong>클릭하여 설계 철학 및 클린룸 경계 안내 펼치기</strong></summary>

1. **연구 및 학습 목적**:
   ProZip은 모던 macOS 데스크톱 GUI 엔지니어링의 최전선을 탐구하기 위해 시작되었습니다. 개발 과정에서 업계 주요 아카이브 유틸리티들의 인터랙션 패턴, 애니메이션 호흡, 다중 엔진 라우팅, 스트리밍 파이프라인을 연구한 뒤 순수 Swift와 SwiftUI로 모든 요소를 독자 설계·구현했습니다.

2. **클린룸 엔지니어링**:
   본 저장소에는 어떠한 독점 상용 소프트웨어의 역컴파일 소스 코드, 보호된 에셋, 비공개 인증서도 포함되어 있지 않습니다. 모든 비즈니스 로직, 데이터 구조, UI 뷰는 클린룸 엔지니어링 원칙에 따라 처음부터 직접 작성되었습니다.

3. **열린 기술 교류 및 비상업적 의도**:
   이 프로젝트는 macOS 데스크톱 앱, 파일 시스템 스트리밍, 네이티브 C/Swift 상호운용성에 관심 있는 개발자 간의 기술 교류를 촉진하기 위해 오픈소스로 공개되었습니다. 모든 상용 소프트웨어 개발자의 지식재산권과 장인 정신을 깊이 존중하며, 본 저장소는 상용 제품을 대체하는 것을 목표로 하지 않습니다.

</details>

---

## 크레딧 및 감사의 말

ProZip은 훌륭한 오픈소스 인프라와 라이브러리를 기반으로 만들어졌습니다. 아래 프로젝트와 메인테이너 여러분께 진심으로 감사드립니다:

| 프로젝트 | 역할 및 기여 | 라이선스 |
|---|---|---|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | 네이티브 Swift ZIP 파싱 및 스트리밍 읽기/쓰기 기반 | MIT |
| [7-Zip / p7zip](https://www.7-zip.org/) | 7z, LZMA2 압축 및 다중 포맷 압축 해제 엔진 | LGPL-2.1+ / unRAR License |
| [libarchive](https://www.libarchive.org/) | 다중 포맷 스트리밍 아카이브 호환 계층 | BSD |
| [libdeflate](https://github.com/ebiggers/libdeflate) | 고성능 Deflate / zlib 압축 레퍼런스 | MIT |

---

## 지원 및 커뮤니티

ProZip이 마음에 드시거나 학습 및 일상 워크플로에 도움이 되었다면:
- GitHub 저장소에 **Star** ⭐️를 눌러 응원해 주세요!
- 버그를 발견했거나 아이디어가 있으신가요? 언제든 [Issue](https://github.com/scoltzero/prozip/issues)를 등록하거나 Pull Request를 보내 주세요!

---

## 라이선스

ProZip 핵심 소스 코드는 **[GNU General Public License v3.0](../../LICENSE)** (GPL-3.0) 라이선스에 따라 배포됩니다.  
참조된 서드파티 오픈소스 구성 요소는 각각의 업스트림 라이선스를 그대로 따릅니다.
