# Änderungsprotokoll

[English](../../CHANGELOG.md) · [简体中文](../zh-CN/CHANGELOG.md) · [繁體中文](../zh-TW/CHANGELOG.md) · [日本語](../ja/CHANGELOG.md) · [한국어](../ko/CHANGELOG.md) · [Español](../es/CHANGELOG.md) · [Français](../fr/CHANGELOG.md) · **Deutsch** · [Русский](../ru/CHANGELOG.md)

Alle nennenswerten Änderungen an **ProZip** werden in dieser Datei dokumentiert.

Das Format basiert auf [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), und dieses Projekt folgt der [Semantischen Versionierung](https://semver.org/lang/de/).

---

## [0.1.5] - 2026-11-23

### Hinzugefügt
- **App-internes Selbst-Update (Herunterladen, Prüfen & Neustarten)**:
  - Schaltfläche **Jetzt aktualisieren** im Dialog „Nach Updates suchen“ hinzugefügt, sodass kein manueller Download und keine Installation per Drag-and-Drop über den Browser mehr nötig sind.
  - Lädt das `.zip`-Paket aus GitHub Releases als Stream mit Live-Fortschritt herunter, überprüft `SHA256SUMS.txt` per `CryptoKit` sowie `CFBundleIdentifier`, entpackt über `/usr/bin/ditto`, tauscht `ProZip.app` atomar aus (mit automatischem Rollback bei Fehlern und Administratorabfrage bei fehlenden Schreibrechten) und startet die App automatisch neu.

### Behoben & Geändert
- **Monochromes Vorlagensymbol in der Menüleiste & Panel-Ausrichtung**:
  - Das farbige Menüleisten-Icon wurde durch ein auflösungsunabhängiges macOS-Vorlagensymbol (`isTemplate = true`) ersetzt, das nur das Marken-**P** und dessen Schatten mit 33 % Deckkraft zeigt und sich automatisch an den hellen und dunklen Modus anpasst.
  - Der obere Innenabstand des Ablagepanels in der Menüleiste wurde verringert und direkt an der Unterkante der Menüleiste verankert, um den übermäßigen Zwischenraum zu beseitigen und die Vorschau in den Einstellungen anzugleichen.
- **Entpackfortschritt in Echtzeit**: Live-Fortschrittsübertragung beim Entpacken von geteilten RAR-Archiven sowie allen unterstützten Archivformaten implementiert.

---

## [0.1.4] - 2026-11-21

### Hinzugefügt
- **Einstellung zum Ein- und Ausblenden im Dock**: Schalter **Im Dock anzeigen** unter Einstellungen → Allgemein → Start hinzugefügt, der `NSApplication.ActivationPolicy` (`.regular` / `.accessory`) im laufenden Betrieb ohne Neustart umschaltet und dabei den Fokus des aktiven Fensters beibehält; außerdem einen Schnellzugriff **Einstellungen…** im Rechtsklickmenü der Menüleisten-Box ergänzt – inklusive Lokalisierungen für Vereinfachtes Chinesisch, Traditionelles Chinesisch und Englisch.
- **Feingranulare Bereinigung der Aufgabenwarteschlange & größenveränderbares Erstellungsfenster**:
  - Schaltflächen zum Entfernen einzelner Aufgaben sowie die Aktionen **Abgeschlossene löschen** (einschließlich fehlgeschlagener Aufgaben) und **Alle löschen** in `ArchiveProgressWindowView` hinzugefügt.
  - `ArchiveCreationDialogView` in ein eigenständiges, frei skalierbares Fenster mit gespeicherter Fenstergröße ausgelagert und die Zeilen zur Dateibereinigung und Namenskompatibilität in der Übersicht direkt anklickbar gemacht.

### Geändert
- **Speicherfreigabe im Leerlauf & null Hintergrund-Wakeups**:
  - Die Titelrotation von `ProZipLandingView` an `isWindowActive` gekoppelt, sodass Fenster im Hintergrund, ohne Fokus oder im minimierten Zustand die Animationsschleife sofort pausieren und im Leerlauf keinerlei CPU-Wakeups verursachen.
  - `NSHostingView`-Hierarchien und Grafikpuffer werden beim Schließen des Willkommensfensters, des Einstellungsfensters (unter Beibehaltung der gemerkten Größe), des Menüleisten-Ablagepanels, des Aufgabenfortschrittsfensters und von Hinweisfenstern aktiv freigegeben; zudem wird das Willkommensfenster nicht mehr vorab im Hintergrund erzeugt, wenn bereits eine aktive Archivsitzung besteht.
  - `ProZipResourceImageLoader` auf einen kapazitätsbegrenzten `NSCache` umgestellt (wird beim Schließen der Einstellungen geleert) und das Statussymbol in der Menüleiste in `18×18` gerastert, statt die vollständige `512×512`-Quellbitmap im Speicher zu halten.
- **Streaming-Komprimierungsfortschritt in Echtzeit & Engine-Vorwärmung**: Fortschrittsmeldungen in 512-KiB-Blöcken in `NativeZipEngine` sowie `-bsp1`-Live-Fortschrittsstreaming in `SevenZipEngine` ergänzt (inklusive Weitergabe der konfigurierten `-mmt`-Thread-Anzahl und der Ausschlussregeln `-xr!.DS_Store/__MACOSX/._*`), begleitet von einer Hintergrund-Vorwärmung der Engines außerhalb von `@MainActor`.

---

## [0.1.3] - 2026-11-14

### Hinzugefügt
- **Leertasten-Umschaltung im Finder für ProZip Mini**: `FinderSpacebarMonitor` auf Basis der macOS-Berechtigungen für Bedienungshilfen und Automation (`AppleEvents`) hinzugefügt, sodass ein Druck auf die Leertaste bei einem ausgewählten unterstützten Archiv im Finder direkt ProZip Mini öffnet und ein erneuter Druck in Mini das Fenster schließt und den Fokus an den Finder zurückgibt – konfigurierbar mit Berechtigungs-Assistent und Formatwahl unter Einstellungen → ProZip Mini.
- **Schlüsselbund-Autorisierungswiederherstellung & Reset-Fallback für den Passworttresor**: Bewahrt bestehende verschlüsselte Tresore, wenn ein Open-Source- oder Ad-hoc-signiertes Binary ältere Schlüsselbund-ACLs (`Keychain`) ungültig macht; ergänzt um **Passworttresor autorisieren & wiederherstellen** (fragt einmalig über den System-Schlüsselbunddialog an, entschlüsselt gespeicherte Einträge und rotiert auf einen neuen, an die aktuelle App-Signatur gebundenen Schlüssel für künftigen stillen Zugriff) sowie den zweistufigen Fallback **Passworttresor zurücksetzen & neu erstellen** unter Einstellungen → Passworttresor und im Schutzdialog.

### Geändert
- **Archivgröße in der Kopfzeile von ProZip Mini**: Der Untertitel des Mini-Fensters zeigt nun sowohl die Eintragsanzahl als auch die formatierte Gesamtgröße der Archivdatei an.
- **Behandlung von Ad-hoc-Builds für die Touch-ID-Schnellentsperrung**: Deaktiviert den Schalter für die Touch-ID-Schnellentsperrung in Builds ohne Apple Team ID sauber mit entsprechendem Hinweis, während die vollständige Data-Protection-Keychain-Implementierung für künftig signierte kommerzielle Builds erhalten bleibt.
- **Interaktives Demo-GIF in der README**: `Resources/ProZip-Demo.gif` in [README.md](README.md) eingefügt, um UI-Modi und Arbeitsabläufe vorzustellen.

### Behoben
- Problem behoben, bei dem das Ziehen am Kopfbereich, Fußbereich oder Hintergrund des Dialogs für Archiverstellungsoptionen (`ArchiveCreationDialogView`) das übergeordnete Fenster nicht verschob (Auflösung der Elternfensterkette über `WindowDragArea.resolveRootWindow` + Maus-Drag-Tracking).
- Fehler behoben, durch den die Leertaste das ProZip-Mini-Fenster nach dem Öffnen über die Leertasten-Vorschau im Finder nicht wieder schloss.

---

## [0.1.2] - 2026-11-12

### Hinzugefügt
- **Automatischer Update-Dienst über GitHub Releases & UI-Integration**: `AppUpdateService` eingeführt, um die GitHub-Releases-API abzufragen, semantische Versionsvergleiche durchzuführen, Zusammenfassungen der Versionshinweise anzuzeigen und direkte `.dmg`- / `.zip`-Download-Links zu öffnen – integriert im Dialog „Nach Updates suchen“, unter Einstellungen → Über sowie als stille Prüfung beim Start (auf alle 24 Stunden gedrosselt).
- **Natives Liquid-Glass-Designsystem für macOS 26+**: Einheitliche kapsel-, kreis- und kontinuierlich abgerundete Liquid-Glass-Modifikatoren auf Basis von nativem `.glassEffect` und `GlassEffectContainer` entwickelt, mit sanftem Milchglas-Fallback für macOS 14–15.

### Geändert
- **Optische Lichtbrechung & Interaktions-Feinschliff im Mini-Fenster**:
  - Liquid-Glass-Kantenbrechung des Mini-Fensters, kontinuierlichen `20pt`-Eckenradius und Lichtdurchlässigkeit vor hellen und dunklen Hintergründen kalibriert und Rahmenartefakte in den Fensterecken beseitigt.
  - Die runden Bedienelemente unten links (Schließen, Anheften mit himmelblauem Leuchtring, Erweitern) sowie die Kapsel `Vorschau + Alles entpacken` unten rechts auf natives interaktives Liquid Glass umgestellt – mit sanfter segmentweiser Hover-Einfärbung und gerichteter Linsenreaktion beim Klicken.
  - Die vertikale Bildlaufleiste im Mini-Fenster transparent gestaltet und die untere Ausblendmaske verfeinert.
- **Liquid-Glass-Upgrade für Arbeitsbereich & Willkommensfenster**:
  - Die Kapsel zur Ansichtsumschaltung oben rechts, die runden Schaltflächen Löschen/Speichern/Suchen (einschließlich der aktiven karmesinroten Löschen-Glasschaltfläche und der ausgeklappten Suchleiste), die Breadcrumb-Navigationsleiste und die Aktionsleiste unten links auf natives Liquid Glass aktualisiert.
  - Den statischen weißen Schleier am unteren Rand sowie überflüssige vertikale Trennlinien im Arbeitsbereich entfernt, sodass scrollende Dateizeilen direkt durch die schwebende Liquid-Glass-Kapsel gebrochen werden.
  - Den leuchtenden Glasrand der primären Flow-Aktion und den gestapelten Kartenindikator verfeinert, sodass die sekundäre Aktion `Entpacken` beim Überfahren sanft ausklappt.
  - Die Bedienelemente `Archiv öffnen`, `Archiv erstellen` und `Einstellungen` im Willkommensfenster einheitlich auf natives Liquid Glass umgestellt.

### Behoben
- Problem behoben, bei dem Tastenkürzel-Badges (`⏎` / `Leertaste`) in der unteren Aktionskapsel des Arbeitsbereichs beim Überfahren mit der Maus weiß auf weiß dargestellt wurden.

---

## [0.1.0] - 2026-11-12

### Hinzugefügt
- **Erste Open-Source-Veröffentlichung (GPL-3.0)**:
  - Vierstufige Archiv-Engine-Architektur aus `NativeZipEngine` (reiner Zero-Copy-ZIP-Reader in Swift), 7-Zip (Multi-Thread-LZMA2), System-`libarchive` und dem Einbinden von Disk-Images per `hdiutil`.
  - Hochschnelle hierarchische SQLite-Eintragsindexierung (`EntryIndex`) zum sofortigen Durchsuchen und Filtern großer Archive.
  - Nahtloser Dual-Mode-Workflow (`⌥⌘M`) zwischen dem `1040×740` großen Arbeitsbereich mit drei Ansichten (Symbole, Liste, Spalten) und dem kompakten `560×422`-Mini-Browser.
  - Kontextsensitive Flow-Empfehlungs-Engine (App-Bundle-Installation, Schriftinstallation, sicheres direktes Öffnen per Positivliste und Ein-Klick-Entpacken).
  - Dauerhaftes Ablagefach in der Menüleiste (Shelf) zum Sammeln per Drag-and-Drop aus mehreren Quellen, direkten Durchsuchen von Ordnern und Archiven sowie zum Stapelkomprimieren und -entpacken.
  - Lokaler AES-GCM-verschlüsselter Passworttresor auf Basis des macOS-Schlüsselbunds (`Keychain`), Entsperrung per Touch ID und automatischem Passwortabgleich.
  - Integrierte Finder-Kontextmenü-Erweiterung (`ProZipFinderSync`) und Übersicht-Vorschau-Erweiterung (`ProZipQuickLook`).

[0.1.5]: https://github.com/scoltzero/prozip/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/scoltzero/prozip/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/scoltzero/prozip/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/scoltzero/prozip/compare/v0.1.0...v0.1.2
[0.1.0]: https://github.com/scoltzero/prozip/releases/tag/v0.1.0
