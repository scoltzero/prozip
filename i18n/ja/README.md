<p align="center">
  <img src="../../Resources/AppIcon-Preview.png" alt="ProZip Logo" width="160">
</p>

<h1 align="center">ProZip</h1>

<p align="center">
  <strong>モダンで洗練された、macOS 向け高性能オープンソース・アーカイブマネージャー</strong><br>
  ネイティブ Swift &amp; SwiftUI 製 · 4層エンジンパイプライン · 高速 SQLite インデックス · システム拡張との深い統合
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="../zh-CN/README.md">简体中文</a> ·
  <a href="../zh-TW/README.md">繁體中文</a> ·
  <strong>日本語</strong> ·
  <a href="../ko/README.md">한국어</a> ·
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
  <a href="https://github.com/scoltzero/prozip/releases/latest"><img src="https://img.shields.io/badge/Download-Latest%20Release-0969DA?style=for-the-badge&logo=github&logoColor=white" alt="最新リリースをダウンロード"></a>
  <a href="#クイックスタート"><img src="https://img.shields.io/badge/Guide-Quick%20Start-334155?style=for-the-badge&logo=readthedocs&logoColor=white" alt="クイックスタート"></a>
  <a href="https://github.com/scoltzero/prozip/issues"><img src="https://img.shields.io/badge/Feedback-Issues-2EA44F?style=for-the-badge&logo=github&logoColor=white" alt="フィードバックと Issue"></a>
</p>

<p align="center">
  <img src="../../Resources/ProZip-Demo.gif" alt="ProZip UI と機能の紹介デモ" width="920">
</p>

> [!IMPORTANT]
> **プロジェクトの位置づけと目的**：
> ProZip は、モダンな macOS デスクトップアーキテクチャ、SwiftUI と AppKit のハイブリッドなインタラクション設計、複数エンジンを横断するアーカイブストリーミングパイプライン、およびクリーンルーム開発手法の学習・研究・技術探求を目的として独立開発された、完全オープンソースのプロジェクトです。
>
> 本ソフトウェアは技術交流および教育目的のみで公開されており、市場にある商用のアーカイブ管理ソフトウェアと競合することを意図していません。すべてのコードは商用の逆コンパイルコードや無許諾のアセットを一切含まずゼロから独自に実装されており、[GNU General Public License v3.0](../../LICENSE) の下で公開されています。macOS 開発者やオープンソースコントリビューターの皆様からの議論・フィードバック・改善へのご参加を心より歓迎します。

---

## ProZip の特長

| 主な機能 | 説明 |
|---|---|
| **ネイティブの高速動作と洗練された外観** | 純粋な Swift と SwiftUI で構築され、macOS 本来の視覚階層、Liquid Glass の光学表現、軽快な操作レスポンスを実現。 |
| **4層エンジンの連携パイプライン** | `NativeZipEngine`（ゼロコピー直接読み取り）、7-Zip（マルチスレッド LZMA2）、システムの `libarchive`、および `hdiutil` によるディスクイメージマウントを統合。 |
| **高速な2テーブル構成 SQLite インデックス** | アーカイブを開いた瞬間にローカルの階層インデックス DB を構築。数万件のエントリでもミリ秒単位で展開・絞り込み・選択解凍が可能。 |
| **柔軟なデュアルモード・ワークスペース** | 高機能な `1040×740` マルチカラム Workspace と、コンパクトな `560×422` フロスト調 Mini ブラウザをシームレスに切り替え（`⌥⌘M`）。 |
| **コンテキスト認識型スマート Flow** | アーカイブの中身（アプリ、フォント、書類など）を自動判別し、**アプリケーションにインストール**、**フォントをインストール**、直接開くなどの最適な操作を提案。 |
| **メニューバーの一時保管シェルフ（ProZip Box）** | メニューバーに常駐するドロップゾーン。複数フォルダからのファイル収集、フォルダ階層のインライン閲覧、ワンクリックでの一括圧縮に対応。 |
| **安全なパスワードブックと Touch ID** | macOS キーチェーンと Touch ID で保護されたローカル AES-GCM 暗号化ボールトを搭載。アーカイブ解錠時には登録パスワードを自動で順次照合。 |
| **システム拡張との深い統合** | Finder コンテキストメニュー拡張機能（`FinderSync`）と、スペースキーによるクイックルック（`Quick Look`）高速プレビュープラグインを同梱。 |

---

## 対応フォーマット一覧

| カテゴリ | 対応フォーマットと機能 |
|---|---|
| **展開・閲覧** | ZIP, 7Z, RAR (v4 / v5 / 分割ボリューム), TAR, GZ, TGZ, BZ2, TBZ2, XZ, TXZ, ZST, TZST, CPIO, CAB, ISO, DMG ほか |
| **アーカイブ作成** | ZIP（Deflate 圧縮レベル調整、AES-256 暗号化、分割ボリューム）、7Z（高圧縮率 LZMA2、ヘッダ暗号化、分割ボリューム）、TAR |
| **インプレース編集・保存** | 既存の単一ボリュームアーカイブ内でエントリの追加・削除・名前変更を直接実行（アトミックなコミットトランザクションと自動ロールバック保護付き） |

---

## システム要件

- **OS**：macOS 14.0 (Sonoma) 以降
- **アーキテクチャ**：Apple Silicon（M シリーズ）ネイティブおよび Intel（`x86_64`）対応
- **プライバシーと動作環境**：100% ローカル・オフライン動作。ネットワーク追跡、テレメトリ、外部解析の送信はデフォルトで一切なし

---

## クイックスタート

### 1. ビルド済みリリースのダウンロード
[Latest Release](https://github.com/scoltzero/prozip/releases/latest) ページから `ProZip-v0.1.5-macos.dmg` または `ProZip-v0.1.5-macos.zip` をダウンロードします（変更履歴は [CHANGELOG.md](CHANGELOG.md) を参照してください）。

### 2. インストールと起動
1. `.dmg` ディスクイメージを開き、`ProZip.app` を `Applications`（アプリケーション）フォルダへドラッグします。
2. ProZip をダブルクリックして起動します。macOS で未確認の開発元に関する警告が表示された場合は、**システム設定 → プライバシーとセキュリティ** を開き、**このまま開く** をクリックしてください。
3. 初回起動時のオンボーディングウィザードに従い、必要に応じて Finder 拡張機能とクイックルック（Quick Look）プレビュープラグインを有効化します。

---

## アーキテクチャ

ProZip は、UI 表示、セッション状態、エントリインデックス、および低レイヤーのアーカイブエンジンを明確に分離したクリーンなレイヤードアーキテクチャを採用しています。

```text
┌─────────────────────────────────────────────────────────────┐
│              ProZip App & Extensions Layer                  │
│   (WorkspaceWindowView / MiniWindowView / MenuBarShelf)     │
│   (ProZipFinderSync Extension / ProZipQuickLook Plugin)     │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    ProZipUI & ViewModels                    │
│   - AppViewModel (セッション制御・状態遷移・Flow 判定)      │
│   - ProZipTheme (ネイティブ外観・配色階層・モーション)      │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    ProZipCore Engine Layer                  │
│   - ArchiveBrowsingSession (セッション管理とステージング)   │
│   - EntryIndex (高速 SQLite ディレクトリ・項目索引)         │
│   - PasswordBook (AES-GCM + Keychain + Touch ID 保管庫)     │
│   - ManagedTemporaryArtifactRegistry (一時ファイルの管理)   │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                   Archive Engine Broker                     │
│   ├─ NativeZipEngine   : Swift ネイティブ直読・高速書込     │
│   ├─ SevenZipEngine    : 7-Zip LZMA2 / AES / 多形式対応     │
│   ├─ LibarchiveEngine  : システム libarchive ストリーム層   │
│   └─ DiskImageEngine   : hdiutil ディスクイメージマウント   │
└─────────────────────────────────────────────────────────────┘
```

---

## ソースからのビルド

ProZip は Swift Package Manager で管理されており、自動パッケージングスクリプトが含まれています。

### 前提条件
- macOS 14.0 以降、および Xcode 15 以降または Xcode Command Line Tools
- Homebrew でインストールした `7zz`（同梱する 7-Zip エンジンサブセットの抽出に使用）：
  ```bash
  brew install sevenzip
  ```

### ビルド手順
1. **リポジトリをクローン**：
   ```bash
   git clone https://github.com/scoltzero/prozip.git
   cd prozip
   ```

2. **コア Swift モジュールをビルド**：
   ```bash
   swift build -c release
   ```

3. **完全な macOS `.app` バンドルをパッケージング**（Finder 拡張機能およびクイックルック拡張機能を含む）：
   ```bash
   bash scripts/build_app.sh release
   ```
   完了すると、`build/ProZip.app` にアプリケーションバンドルが生成されます。

---

## 独自実装およびオープンソースに関する声明

<details>
<summary><strong>クリックして設計思想とクリーンルーム開発の境界を表示</strong></summary>

1. **研究・学習目的**：
   ProZip は、モダンな macOS デスクトップ GUI エンジニアリングの最前線を探求するために開始されました。開発にあたっては、業界の優れたアーカイブユーティリティにおける操作パターン、アニメーションの緩急、マルチエンジンルーティング、ストリーミングパイプラインを研究したうえで、純粋な Swift と SwiftUI により独自に設計・実装しています。

2. **クリーンルーム・エンジニアリング**：
   本リポジトリには、いかなるプロプライエタリソフトウェアの逆コンパイルソースコード、保護されたアセット、秘密証明書も一切含まれていません。すべてのビジネスロジック、データ構造、UI ビューはクリーンルーム原則に基づきゼロから記述されています。

3. **オープンな技術交流と非商用方針**：
   本プロジェクトは、macOS デスクトップアプリ、ファイルシステムストリーミング、ネイティブ C/Swift 相互運用に関心を持つ開発者同士の技術交流を促進するために公開されています。すべての商用ソフトウェア開発者の知的財産と職人技に深い敬意を払っており、いかなる商用製品の代替も目的としていません。

</details>

---

## クレジット・謝辞

ProZip は優れたオープンソース基盤およびライブラリの上に成り立っています。以下のプロジェクトとメンテナの皆様に深く感謝いたします。

| プロジェクト | 役割・貢献 | ライセンス |
|---|---|---|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | ネイティブ Swift による ZIP 解析およびストリーミング読み書き基盤 | MIT |
| [7-Zip / p7zip](https://www.7-zip.org/) | 7z・LZMA2 圧縮およびマルチフォーマット展開エンジン | LGPL-2.1+ / unRAR License |
| [libarchive](https://www.libarchive.org/) | マルチフォーマット・ストリーミングアーカイブ互換レイヤー | BSD |
| [libdeflate](https://github.com/ebiggers/libdeflate) | 高性能 Deflate / zlib 圧縮リファレンス | MIT |

---

## サポートとコミュニティ

ProZip を気に入っていただけた場合や、学習・日々のワークフローでお役に立った場合はぜひ応援してください。
- GitHub でリポジトリに **Star** ⭐️ を付けてサポートをお願いします！
- バグ報告や改善のアイデアがありましたら、お気軽に [Issue](https://github.com/scoltzero/prozip/issues) や Pull Request をお寄せください！

---

## ライセンス

ProZip のコアソースコードは **[GNU General Public License v3.0](../../LICENSE)** (GPL-3.0) の下でライセンスされています。  
参照しているサードパーティ製オープンソースコンポーネントには、それぞれの上流ライセンスが引き続き適用されます。
