<p align="center">
  <img src="../../Resources/AppIcon-Preview.png" alt="Logo ProZip" width="160">
</p>

<h1 align="center">ProZip</h1>

<p align="center">
  <strong>Un gestionnaire d’archives open source moderne, élégant et haute performance pour macOS</strong><br>
  Conçu en Swift et SwiftUI natifs · Architecture à quatre moteurs · Indexation SQLite instantanée · Extensions système profondes
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="../zh-CN/README.md">简体中文</a> ·
  <a href="../zh-TW/README.md">繁體中文</a> ·
  <a href="../ja/README.md">日本語</a> ·
  <a href="../ko/README.md">한국어</a> ·
  <a href="../es/README.md">Español</a> ·
  <strong>Français</strong> ·
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
  <a href="https://github.com/scoltzero/prozip/releases/latest"><img src="https://img.shields.io/badge/Download-Latest%20Release-0969DA?style=for-the-badge&logo=github&logoColor=white" alt="Télécharger la dernière version"></a>
  <a href="#démarrage-rapide"><img src="https://img.shields.io/badge/Guide-Quick%20Start-334155?style=for-the-badge&logo=readthedocs&logoColor=white" alt="Démarrage rapide"></a>
  <a href="https://github.com/scoltzero/prozip/issues"><img src="https://img.shields.io/badge/Feedback-Issues-2EA44F?style=for-the-badge&logo=github&logoColor=white" alt="Retours et tickets"></a>
</p>

<p align="center">
  <img src="../../Resources/ProZip-Demo.gif" alt="Présentation de l’interface et des fonctionnalités de ProZip" width="920">
</p>

> [!IMPORTANT]
> **Positionnement et objectif du projet** :
> ProZip est un projet indépendant et entièrement open source créé à des fins d’apprentissage, de recherche et d’exploration technique autour de l’architecture moderne des applications de bureau macOS, de la conception d’interactions hybride SwiftUI + AppKit, des pipelines de lecture en flux inter-moteurs et de l’ingénierie logicielle en salle blanche (*clean-room*).
>
> Ce logiciel est destiné uniquement à l’échange technique et à des fins pédagogiques, et n’a pas vocation à concurrencer les logiciels d’archivage commerciaux existants sur le marché. Chaque ligne de code est écrite de manière indépendante à partir de zéro, sans code source commercial décompilé ni ressources non autorisées, et est publiée sous licence [GNU General Public License v3.0](../../LICENSE). Les développeurs macOS et les contributeurs open source sont chaleureusement invités à l’explorer, en discuter et l’améliorer ensemble.

---

## Pourquoi choisir ProZip

| Fonctionnalité clé | Description |
|---|---|
| **Performances et finition natives** | Conçu intégralement en Swift et SwiftUI avec la hiérarchie visuelle native de macOS, le rendu optique Liquid Glass et un retour tactile réactif. |
| **Synergie à quatre moteurs** | Associe `NativeZipEngine` (lecteur direct sans copie), 7-Zip (LZMA2 multithread), `libarchive` système et le montage d’images disque via `hdiutil`. |
| **Indexation SQLite instantanée à double table** | Construit une base d’index hiérarchique locale dès l’ouverture d’une archive : développez, filtrez et extrayez sélectivement des dizaines de milliers d’entrées en quelques millisecondes. |
| **Espace de travail flexible à double mode** | Basculez instantanément (`⌥⌘M`) entre l’espace de travail multicolonne complet (`1040×740`) et le navigateur compact dépoli Mini (`560×422`). |
| **Flux intelligent contextuel (Flow)** | Analyse automatiquement le contenu de l’archive (apps, polices, documents, etc.) et recommande des actions adaptées comme **Installer dans Applications**, **Installer la police** ou l’ouverture directe. |
| **Zone de dépôt dans la barre des menus (ProZip Box)** | Zone de glisser-déposer toujours accessible dans la barre des menus pour rassembler des fichiers issus de plusieurs dossiers, parcourir les répertoires en ligne et compresser par lots en un clic. |
| **Carnet de mots de passe sécurisé et Touch ID** | Coffre-fort local chiffré en AES-GCM protégé par le Trousseau (Keychain) de macOS et Touch ID, avec essai automatique de plusieurs mots de passe lors du déverrouillage d’archives. |
| **Extensions système profondes** | Intègre une extension de menu contextuel du Finder (`FinderSync`) et un module d’aperçu instantané Coup d’œil (`Quick Look`) via la barre d’espace. |

---

## Matrice des formats pris en charge

| Catégorie | Formats et capacités pris en charge |
|---|---|
| **Extraction et navigation** | ZIP, 7Z, RAR (v4 / v5 / multivolume), TAR, GZ, TGZ, BZ2, TBZ2, XZ, TXZ, ZST, TZST, CPIO, CAB, ISO, DMG et plus encore |
| **Création d’archives** | ZIP (niveau de compression Deflate configurable, chiffrement AES-256, volumes fractionnés), 7Z (taux élevé LZMA2, chiffrement des en-têtes, volumes fractionnés), TAR |
| **Modification et enregistrement sur place** | Ajoutez, supprimez et renommez des entrées directement dans les archives monovolume existantes grâce à des transactions atomiques et une restauration automatique en cas d’erreur |

---

## Configuration requise

- **Système d’exploitation** : macOS 14.0 (Sonoma) ou version ultérieure
- **Architecture** : Compatibilité native Apple Silicon (puces série M) et Intel (`x86_64`)
- **Confidentialité et environnement** : Exécution 100 % locale hors ligne ; aucun suivi réseau, aucune télémétrie ni analyse distante activée par défaut

---

## Démarrage rapide

### 1. Télécharger une version précompilée
Rendez-vous sur la page de la [dernière version (Latest Release)](https://github.com/scoltzero/prozip/releases/latest) pour télécharger `ProZip-v0.1.5-macos.dmg` ou `ProZip-v0.1.5-macos.zip` (consultez [CHANGELOG.md](CHANGELOG.md) pour les notes de version).

### 2. Installer et lancer
1. Ouvrez l’image disque `.dmg` et faites glisser `ProZip.app` dans votre dossier `Applications`.
2. Double-cliquez pour ouvrir ProZip. Si macOS affiche un avertissement concernant un développeur non identifié, accédez à **Réglages Système → Confidentialité et sécurité**, puis cliquez sur **Ouvrir quand même**.
3. Suivez l’assistant de premier lancement pour activer l’extension du Finder et le module d’aperçu Coup d’œil (`Quick Look`) selon vos besoins.

---

## Architecture

ProZip adopte une architecture en couches claire qui découple la présentation de l’interface, l’état de session, l’indexation des entrées et les moteurs d’archivage bas niveau :

```text
┌─────────────────────────────────────────────────────────────┐
│              ProZip App & Extensions Layer                  │
│   (WorkspaceWindowView / MiniWindowView / MenuBarShelf)     │
│   (ProZipFinderSync Extension / ProZipQuickLook Plugin)     │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    ProZipUI & ViewModels                    │
│   - AppViewModel (Orchestration de session et actions Flow) │
│   - ProZipTheme (Style natif, couleurs et animations)       │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                    ProZipCore Engine Layer                  │
│   - ArchiveBrowsingSession (Cycle de session et transit)    │
│   - EntryIndex (Index SQLite rapide dossiers et entrées)    │
│   - PasswordBook (Coffre AES-GCM + Trousseau + Touch ID)    │
│   - ManagedTemporaryArtifactRegistry (Fichiers temporaires) │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│                   Archive Engine Broker                     │
│   ├─ NativeZipEngine   : Lecture/écriture directe en Swift  │
│   ├─ SevenZipEngine    : 7-Zip LZMA2 / AES / multiformat    │
│   ├─ LibarchiveEngine  : Flux libarchive système            │
│   └─ DiskImageEngine   : Montage d'images disque hdiutil    │
└─────────────────────────────────────────────────────────────┘
```

---

## Compilation depuis les sources

ProZip est géré avec Swift Package Manager et inclut des scripts d’empaquetage automatisés :

### Prérequis
- macOS 14.0+ avec Xcode 15+ ou les outils en ligne de commande Xcode installés
- `7zz` installé via Homebrew (utilisé pour intégrer le sous-ensemble du moteur 7-Zip embarqué) :
  ```bash
  brew install sevenzip
  ```

### Étapes de compilation
1. **Cloner le dépôt** :
   ```bash
   git clone https://github.com/scoltzero/prozip.git
   cd prozip
   ```

2. **Compiler les modules Swift principaux** :
   ```bash
   swift build -c release
   ```

3. **Empaqueter le bundle `.app` macOS complet** (incluant les extensions Finder Sync et Coup d’œil) :
   ```bash
   bash scripts/build_app.sh release
   ```
   Une fois terminé, le paquet de l’application est disponible dans `build/ProZip.app`.

---

## Implémentation indépendante et déclaration open source

<details>
<summary><strong>Cliquer pour afficher la philosophie de conception et le cadre clean-room</strong></summary>

1. **Objectif de recherche et d’apprentissage** :
   ProZip a vu le jour pour explorer les frontières de l’ingénierie d’interfaces graphiques modernes sur macOS. Au cours du développement, nous avons étudié les modèles d’interaction, le rythme des animations, le routage multimoteur et les pipelines de flux des principaux utilitaires d’archivage du secteur, avant de tout concevoir et implémenter de manière indépendante en Swift et SwiftUI purs.

2. **Ingénierie en salle blanche (Clean-Room)** :
   Ce dépôt ne contient aucun code source décompilé, aucune ressource protégée ni aucun certificat privé provenant d’un logiciel propriétaire. Toute la logique métier, les structures de données et les vues d’interface sont rédigées à partir de zéro selon les principes d’ingénierie clean-room.

3. **Échange ouvert et vocation non commerciale** :
   Ce projet est publié en open source afin d’encourager le partage technique entre développeurs intéressés par les applications de bureau macOS, le traitement de flux du système de fichiers et l’interopérabilité native C/Swift. Nous respectons profondément la propriété intellectuelle et le savoir-faire de tous les éditeurs de logiciels commerciaux, et ce dépôt ne vise à remplacer aucun produit commercial.

</details>

---

## Crédits et remerciements

ProZip s’appuie sur des infrastructures et bibliothèques open source remarquables. Nos sincères remerciements aux mainteneurs de ces projets :

| Projet | Rôle et contribution | Licence |
|---|---|---|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | Socle natif Swift d’analyse et de lecture/écriture en flux pour ZIP | MIT |
| [7-Zip / p7zip](https://www.7-zip.org/) | Compression 7z, LZMA2 et moteur d’extraction multiformat | LGPL-2.1+ / unRAR License |
| [libarchive](https://www.libarchive.org/) | Couche de compatibilité d’archivage en flux multiformat | BSD |
| [libdeflate](https://github.com/ebiggers/libdeflate) | Référence de compression Deflate / zlib haute performance | MIT |

---

## Soutien et communauté

Si vous appréciez ProZip ou qu’il vous est utile pour apprendre ou au quotidien :
- Attribuez une **Star** ⭐️ au dépôt sur GitHub pour soutenir le projet !
- Vous avez trouvé un bug ou avez une suggestion ? N’hésitez pas à ouvrir une [Issue](https://github.com/scoltzero/prozip/issues) ou à soumettre une Pull Request !

---

## Licence

Le code source principal de ProZip est distribué sous licence **[GNU General Public License v3.0](../../LICENSE)** (GPL-3.0).  
Les composants open source tiers référencés demeurent régis par leurs licences d’origine respectives.
