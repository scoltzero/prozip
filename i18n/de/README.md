<p align="center">
  <img src="../../Resources/AppIcon-Preview.png" alt="ProZip-Logo" width="160">
</p>

<h1 align="center">ProZip</h1>

<p align="center">
  <strong>Ein moderner, eleganter und leistungsstarker Open-Source-Archivmanager für macOS</strong><br>
  Entwickelt mit nativem Swift &amp; SwiftUI · Vierstufige Engine-Pipeline · Sofortige SQLite-Indexierung · Tiefe Systemintegration
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="../zh-CN/README.md">简体中文</a> ·
  <a href="../zh-TW/README.md">繁體中文</a> ·
  <a href="../ja/README.md">日本語</a> ·
  <a href="../ko/README.md">한국어</a> ·
  <a href="../es/README.md">Español</a> ·
  <a href="../fr/README.md">Français</a> ·
  <strong>Deutsch</strong> ·
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
  <a href="https://github.com/scoltzero/prozip/releases/latest"><img src="https://img.shields.io/badge/Download-Latest%20Release-0969DA?style=for-the-badge&logo=github&logoColor=white" alt="Neueste Version herunterladen"></a>
  <a href="#schnellstart"><img src="https://img.shields.io/badge/Guide-Quick%20Start-334155?style=for-the-badge&logo=readthedocs&logoColor=white" alt="Schnellstart"></a>
  <a href="https://github.com/scoltzero/prozip/issues"><img src="https://img.shields.io/badge/Feedback-Issues-2EA44F?style=for-the-badge&logo=github&logoColor=white" alt="Feedback & Issues"></a>
</p>

<p align="center">
  <img src="../../Resources/ProZip-Demo.gif" alt="ProZip Benutzeroberfläche & Funktionsübersicht" width="920">
</p>

> [!IMPORTANT]
> **Positionierung und Zielsetzung des Projekts**:
> ProZip ist ein unabhängiges, vollständig quelloffenes Projekt, das zum Lernen, Forschen und zur technischen Erkundung moderner macOS-Desktop-Architekturen, hybriden Interaktionsdesigns mit SwiftUI + AppKit, Engine-übergreifender Archiv-Streaming-Pipelines und Clean-Room-Softwareentwicklung ins Leben gerufen wurde.
>
> Diese Software dient ausschließlich dem technischen Austausch sowie Bildungszwecken und soll mit keiner kommerziellen Archivierungssoftware auf dem Markt konkurrieren. Jede Codezeile wurde eigenständig von Grund auf neu geschrieben – ohne dekompilierten kommerziellen Quellcode oder unautorisierte Ressourcen – und steht unter der [GNU General Public License v3.0](../../LICENSE). Andere macOS-Entwicklerinnen und -Entwickler sowie Open-Source-Beitragende sind herzlich eingeladen, das Projekt gemeinsam zu erkunden, zu diskutieren und weiterzuentwickeln.

---

## Warum ProZip

| Kernfunktion | Beschreibung |
|---|---|
| **Native Performance & Feinschliff** | Entwickelt in reinem Swift & SwiftUI mit tiefer visueller macOS-Hierarchie, Liquid-Glass-Optik und direktem haptischem Feedback. |
| **Vierstufige Engine-Synergie** | Kombiniert `NativeZipEngine` (direkter Zero-Copy-Reader), 7-Zip (Multi-Thread-LZMA2), System-`libarchive` und das Einbinden von Disk-Images per `hdiutil`. |
| **Sofortige SQLite-Doppeltabellen-Indexierung** | Erstellt beim Öffnen eines Archivs eine lokale hierarchische Indexdatenbank – Zehntausende Einträge lassen sich in Millisekunden aufklappen, filtern und gezielt entpacken. |
| **Flexibler Dual-Mode-Arbeitsbereich** | Nahtloser Wechsel (`⌥⌘M`) zwischen dem vollwertigen mehrspaltigen Arbeitsbereich (`1040×740`) und dem kompakten mattierten Mini-Browser (`560×422`). |
| **Intelligenter kontextsensitiver Flow** | Prüft automatisch den Archivinhalt (Apps, Schriften, Dokumente usw.) und empfiehlt passende Aktionen wie **In Programme installieren**, **Schrift installieren** oder direktes Öffnen. |
| **Menüleisten-Ablagefach (ProZip Box)** | Jederzeit erreichbare Drop-Zone in der Menüleiste zum Sammeln von Dateien aus verschiedenen Ordnern, direkten Durchsuchen von Verzeichnissen und Stapelkomprimieren mit einem Klick. |
| **Sicherer Passworttresor & Touch ID** | Lokaler AES-GCM-verschlüsselter Passworttresor, geschützt durch den macOS-Schlüsselbund (`Keychain`) und Touch ID, mit automatischer Passwortrotation beim Entsperren von Archiven. |
| **Tiefe Systemerweiterungen** | Enthält eine Finder-Kontextmenü-Erweiterung (`FinderSync`) sowie ein Plugin für die sofortige Übersicht (`Quick Look`) per Leertaste. |

---

## Unterstützte Formate

| Kategorie | Unterstützte Formate & Funktionen |
|---|---|
| **Entpacken & Durchsuchen** | ZIP, 7Z, RAR (v4 / v5 / Mehrteil-Archive), TAR, GZ, TGZ, BZ2, TBZ2, XZ, TXZ, ZST, TZST, CPIO, CAB, ISO, DMG und weitere |
| **Archiverstellung** | ZIP (konfigurierbare Deflate-Komprimierungsstufe, AES-256-Verschlüsselung, Teilarchive), 7Z (hohe LZMA2-Kompressionsrate, Header-Verschlüsselung, Teilarchive), TAR |
| **Direktes Bearbeiten & Speichern** | Einträge direkt in bestehenden Einzelarchiven hinzufügen, löschen und umbenennen – abgesichert durch atomare Commit-Transaktionen und automatischen Rollback-Schutz |

---

## Systemvoraussetzungen

- **Betriebssystem**: macOS 14.0 (Sonoma) oder neuer
- **Architektur**: Native Unterstützung für Apple Silicon (M-Serie) und Intel (`x86_64`)
- **Datenschutz & Umgebung**: 100 % lokale Offline-Ausführung – standardmäßig keinerlei Netzwerk-Tracking, Telemetrie oder Fernanalyse

---

## Schnellstart

### 1. Vorkompilierte Version herunterladen
Öffne die Seite [Neueste Version (Latest Release)](https://github.com/scoltzero/prozip/releases/latest) und lade `ProZip-v0.1.5-macos.dmg` oder `ProZip-v0.1.5-macos.zip` herunter (Versionshinweise siehe [CHANGELOG.md](CHANGELOG.md)).

### 2. Installieren & Starten
1. Öffne das `.dmg`-Disk-Image und ziehe `ProZip.app` in deinen Ordner `Applications` (Programme).
2. Öffne ProZip per Doppelklick. Falls macOS einen Hinweis auf einen nicht verifizierten Entwickler anzeigt, wähle **Systemeinstellungen → Datenschutz & Sicherheit** und klicke auf **Dennoch öffnen**.
3. Folge beim ersten Start dem Einrichtungsassistenten, um bei Bedarf die Finder-Erweiterung und das Übersicht-Plugin (`Quick Look`) zu aktivieren.

---

## Architektur

ProZip setzt auf eine saubere Schichtenarchitektur, die UI-Darstellung, Sitzungsstatus, Eintragsindexierung und Low-Level-Archiv-Engines klar voneinander trennt:

```text
┌─────────────────────────────────────────────────────────────┐
│              ProZip App & Extensions Layer                  │
│   (WorkspaceWindowView / MiniWindowView / MenuBarShelf)     │
│   (ProZipFinderSync Extension / ProZipQuickLook Plugin)     │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    ProZipUI & ViewModels                    │
│   - AppViewModel (Sitzungssteuerung & Flow-Entscheidungen)  │
│   - ProZipTheme (Natives Design, Farbhierarchie, Animation) │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    ProZipCore Engine Layer                  │
│   - ArchiveBrowsingSession (Sitzungszyklus & Staging)       │
│   - EntryIndex (Schneller SQLite-Ordner- & Eintragsindex)   │
│   - PasswordBook (AES-GCM + Schlüsselbund + Touch ID)       │
│   - ManagedTemporaryArtifactRegistry (Temp-Dateiverwaltung) │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                   Archive Engine Broker                     │
│   ├─ NativeZipEngine   : Direktes Lesen/Schreiben in Swift  │
│   ├─ SevenZipEngine    : 7-Zip LZMA2 / AES / Multiformat    │
│   ├─ LibarchiveEngine  : System-libarchive-Streaming-Layer  │
│   └─ DiskImageEngine   : Einbinden von Images per hdiutil   │
└─────────────────────────────────────────────────────────────┘
```

---

## Aus dem Quellcode kompilieren

ProZip wird mit dem Swift Package Manager verwaltet und bringt automatisierte Paketierungsskripte mit:

### Voraussetzungen
- macOS 14.0+ mit installiertem Xcode 15+ oder den Xcode Command Line Tools
- Über Homebrew installiertes `7zz` (wird zum Bündeln der eingebetteten 7-Zip-Engine-Teilmenge verwendet):
  ```bash
  brew install sevenzip
  ```

### Build-Schritte
1. **Repository klonen**:
   ```bash
   git clone https://github.com/scoltzero/prozip.git
   cd prozip
   ```

2. **Swift-Kernmodule kompilieren**:
   ```bash
   swift build -c release
   ```

3. **Vollständiges macOS-`.app`-Bundle paketieren** (einschließlich Finder-Sync- und Übersicht-Erweiterungen):
   ```bash
   bash scripts/build_app.sh release
   ```
   Nach Abschluss liegt das fertige App-Bundle unter `build/ProZip.app`.

---

## Eigenständige Implementierung & Open-Source-Erklärung

<details>
<summary><strong>Klicken, um Designphilosophie &amp; Clean-Room-Grundsätze auszuklappen</strong></summary>

1. **Forschungs- und Lernzweck**:
   ProZip entstand mit dem Ziel, die Möglichkeiten moderner macOS-Desktop-GUI-Entwicklung auszuloten. Während der Entwicklung haben wir Interaktionsmuster, Animationsrhythmen, Multi-Engine-Routing und Streaming-Pipelines führender Archivierungswerkzeuge untersucht und anschließend alles eigenständig in reinem Swift und SwiftUI entworfen und umgesetzt.

2. **Clean-Room-Engineering**:
   Dieses Repository enthält keinerlei dekompilierten Quellcode, geschützte Assets oder private Zertifikate proprietärer Software. Sämtliche Geschäftslogik, Datenstrukturen und UI-Ansichten wurden nach Clean-Room-Prinzipien vollständig von Grund auf neu entwickelt.

3. **Offener Austausch & nichtkommerzielle Ausrichtung**:
   Dieses Projekt wird als Open Source veröffentlicht, um den fachlichen Austausch unter Entwicklerinnen und Entwicklern zu fördern, die sich für macOS-Desktop-Apps, Dateisystem-Streaming und native C/Swift-Interoperabilität interessieren. Wir respektieren das geistige Eigentum und die Handwerkskunst aller Hersteller kommerzieller Software ausdrücklich; dieses Repository verfolgt nicht das Ziel, ein kommerzielles Produkt zu ersetzen.

</details>

---

## Danksagungen

ProZip baut auf herausragender Open-Source-Infrastruktur und bewährten Bibliotheken auf. Ein herzlicher Dank gilt den Maintainerinnen und Maintainern dieser Projekte:

| Projekt | Rolle & Beitrag | Lizenz |
|---|---|---|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | Native Swift-Grundlage für ZIP-Parsing sowie Streaming-Lesen und -Schreiben | MIT |
| [7-Zip / p7zip](https://www.7-zip.org/) | 7z-, LZMA2-Komprimierung und Multiformat-Entpack-Engine | LGPL-2.1+ / unRAR License |
| [libarchive](https://www.libarchive.org/) | Multiformat-Streaming-Kompatibilitätsschicht für Archive | BSD |
| [libdeflate](https://github.com/ebiggers/libdeflate) | Hochperformante Referenz für Deflate- / zlib-Komprimierung | MIT |

---

## Unterstützung & Community

Wenn dir ProZip gefällt oder beim Lernen und im Alltag weiterhilft:
- Gib dem Repository auf GitHub gerne einen **Star** ⭐️, um das Projekt zu unterstützen!
- Einen Fehler entdeckt oder eine Idee? Erstelle jederzeit ein [Issue](https://github.com/scoltzero/prozip/issues) oder reiche einen Pull Request ein!

---

## Lizenz

Der Kernquellcode von ProZip steht unter der **[GNU General Public License v3.0](../../LICENSE)** (GPL-3.0).  
Eingebundene Open-Source-Komponenten von Drittanbietern unterliegen weiterhin ihren jeweiligen Upstream-Lizenzen.
