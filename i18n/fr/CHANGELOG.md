# Journal des modifications

[English](../../CHANGELOG.md) · [简体中文](../zh-CN/CHANGELOG.md) · [繁體中文](../zh-TW/CHANGELOG.md) · [日本語](../ja/CHANGELOG.md) · [한국어](../ko/CHANGELOG.md) · [Español](../es/CHANGELOG.md) · **Français** · [Deutsch](../de/CHANGELOG.md) · [Русский](../ru/CHANGELOG.md)

Toutes les modifications notables apportées à **ProZip** sont documentées dans ce fichier.

Le format est basé sur [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et ce projet respecte la [Gestion sémantique de version](https://semver.org/lang/fr/).

---

## [0.1.5] - 2026-11-23

### Ajouté
- **Mise à jour automatique intégrée (téléchargement, vérification et relance)** :
  - Ajout d’un bouton en un clic **Mettre à jour maintenant** dans la boîte de dialogue Rechercher des mises à jour afin d’éviter le téléchargement et l’installation manuels depuis le navigateur.
  - Télécharge en flux l’archive `.zip` de GitHub Releases avec progression en direct, vérifie `SHA256SUMS.txt` via `CryptoKit` et valide `CFBundleIdentifier`, extrait avec `/usr/bin/ditto`, remplace `ProZip.app` de manière atomique (avec restauration automatique en cas d’échec et demande d’autorisation administrateur si nécessaire), puis relance automatiquement l’application.

### Corrigé et modifié
- **Icône monochrome modèle dans la barre des menus et alignement du panneau** :
  - Remplacement de l’icône colorée de la barre des menus par une icône modèle macOS indépendante de la résolution (`isTemplate = true`) ne conservant que le **P** de la marque et son ombre à 33 % d’opacité, s’adaptant automatiquement aux modes clair et sombre.
  - Réduction de la marge supérieure du panneau de dépôt dans la barre des menus et ancrage au bord inférieur de la barre des menus afin d’éliminer l’écart superflu, tout en gardant l’aperçu aligné dans les Réglages.
- **Progression d’extraction en temps réel** : Diffusion en direct de la progression d’extraction pour les archives RAR fractionnées et l’ensemble des formats pris en charge.

---

## [0.1.4] - 2026-11-21

### Ajouté
- **Préférence d’affichage ou de masquage dans le Dock** : Ajout d’une option **Afficher dans le Dock** dans Réglages → Général → Démarrage qui bascule `NSApplication.ActivationPolicy` (`.regular` / `.accessory`) à chaud sans redémarrage tout en préservant le focus de la fenêtre active ; ajout d’un raccourci **Réglages…** au menu contextuel (clic secondaire) de ProZip Box dans la barre des menus, avec localisations en chinois simplifié, chinois traditionnel et anglais.
- **Nettoyage granulaire de la file de tâches et fenêtre autonome redimensionnable de création** :
  - Ajout de boutons de retrait individuel par tâche, ainsi que des actions **Effacer les tâches terminées** (incluant les tâches échouées) et **Tout effacer** dans `ArchiveProgressWindowView`.
  - Hébergement de `ArchiveCreationDialogView` dans une fenêtre autonome redimensionnable mémorisant ses dimensions, et transformation des lignes de nettoyage et de compatibilité du résumé en bascules directement interactives.

### Modifié
- **Récupération de mémoire au repos et zéro réveil en arrière-plan** :
  - Association de la rotation des titres de `ProZipLandingView` à `isWindowActive` afin que les fenêtres en arrière-plan, hors focus ou réduites suspendent immédiatement la boucle d’animation sans aucun réveil CPU au repos.
  - Libération des hiérarchies `NSHostingView` et des tampons graphiques lors de la fermeture de la fenêtre d’accueil, de la fenêtre des Réglages (tout en conservant la taille mémorisée), du panneau de dépôt de la barre des menus, du panneau de progression des tâches et des fenêtres d’alerte ; évite également de matérialiser prématurément la fenêtre d’accueil lorsqu’une session d’archive est déjà active.
  - Conversion de `ProZipResourceImageLoader` vers un `NSCache` à coût borné (vidé à la fermeture de la fenêtre des Réglages) et rastérisation de l’icône d’état de la barre des menus en `18×18` au lieu de conserver l’image bitmap source complète en `512×512`.
- **Progression de compression en flux en temps réel et préchauffage des moteurs** : Ajout du suivi de progression par blocs de 512 Kio dans `NativeZipEngine` et du flux de progression en direct `-bsp1` dans `SevenZipEngine` (transmettant le nombre de threads `-mmt` configuré ainsi que les exclusions `-xr!.DS_Store/__MACOSX/._*`), accompagné d’un préchauffage des moteurs en arrière-plan hors de `@MainActor`.

---

## [0.1.3] - 2026-11-14

### Ajouté
- **Bascule par barre d’espace dans le Finder pour ProZip Mini** : Ajout de `FinderSpacebarMonitor` s’appuyant sur les autorisations Accessibilité et Automatisation (`AppleEvents`) de macOS afin qu’appuyer sur la barre d’espace dans le Finder sur une archive compatible ouvre directement ProZip Mini, et qu’un nouvel appui sur la barre d’espace dans Mini ferme la fenêtre et rende le focus au Finder ; configurable avec assistant d’autorisations et sélecteurs de formats dans Réglages → ProZip Mini.
- **Récupération d’autorisation du Trousseau et réinitialisation de secours pour le carnet de mots de passe** : Préserve les coffres chiffrés existants lorsqu’un binaire open source ou re-signé ad hoc invalide les anciennes listes ACL du Trousseau (Keychain) ; ajout de **Autoriser et récupérer le carnet de mots de passe** (demande une seule fois l’autorisation via l’interface du Trousseau système, déchiffre les entrées enregistrées et effectue une rotation vers une nouvelle clé liée à la signature actuelle de l’app pour les prochains lancements silencieux) ainsi que d’une option de secours en deux étapes **Réinitialiser et reconstruire le carnet de mots de passe** dans Réglages → Carnet de mots de passe et dans la boîte de dialogue de protection.

### Modifié
- **Taille de l’archive dans l’en-tête de ProZip Mini** : Mise à jour du sous-titre de la fenêtre Mini pour afficher à la fois le nombre d’éléments et la taille formatée du fichier d’archive.
- **Gestion des builds ad hoc pour le déverrouillage rapide Touch ID** : Désactive proprement l’option de déverrouillage rapide Touch ID dans les builds dépourvus de Team ID Apple tout en conservant intacte l’implémentation complète de Data Protection Keychain pour les futures versions commerciales signées.
- **GIF de démonstration interactif dans le README** : Ajout de `Resources/ProZip-Demo.gif` dans [README.md](README.md) pour présenter les modes d’interface et les flux de travail.

### Corrigé
- Correction d’un problème où faire glisser l’en-tête, le pied de page ou l’arrière-plan de la feuille d’options de création d’archive (`ArchiveCreationDialogView`) ne déplaçait pas la fenêtre hôte (résolution de la chaîne parente via `WindowDragArea.resolveRootWindow` + suivi du glissement de la souris).
- Correction d’un problème empêchant la barre d’espace de fermer la fenêtre ProZip Mini après une ouverture via l’aperçu par barre d’espace depuis le Finder.

---

## [0.1.2] - 2026-11-12

### Ajouté
- **Service de mise à jour automatique GitHub Releases et intégration à l’interface** : Introduction de `AppUpdateService` pour interroger l’API GitHub Releases, comparer les versions sémantiques, afficher un résumé des notes de version et ouvrir les liens de téléchargement directs `.dmg` / `.zip`, intégré à la boîte de dialogue Rechercher des mises à jour, au volet Réglages → À propos et aux vérifications silencieuses au lancement limitées à une fois par 24 heures.
- **Système de design Liquid Glass natif pour macOS 26+** : Création de modificateurs Liquid Glass unifiés en capsule, cercle et coins continus reposant sur `.glassEffect` et `GlassEffectContainer` natifs, avec repli harmonieux sur des matériaux dépolis pour macOS 14–15.

### Modifié
- **Réfraction optique et raffinement des interactions de la fenêtre Mini** :
  - Calibration de la réfraction des bords Liquid Glass de la fenêtre Mini, du rayon de coin continu de `20pt` et de la translucidité sur fonds clairs et sombres, éliminant les artefacts d’encadrement dans les angles.
  - Mise à niveau des commandes circulaires en bas à gauche (Fermer, Épingler avec halo bleu ciel, Agrandir) et de la capsule en bas à droite `Aperçu + Tout extraire` vers Liquid Glass interactif natif avec teinte douce par segment au survol et effet de lentille directionnel à l’appui.
  - Rendu transparent du rail de défilement vertical de Mini et affinage du masque de fondu progressif inférieur.
- **Mise à niveau Liquid Glass de l’espace de travail et de la fenêtre d’accueil** :
  - Passage au Liquid Glass natif pour la capsule supérieure droite de changement de vue, les boutons circulaires Supprimer/Enregistrer/Rechercher (y compris le bouton de verre cramoisi actif Supprimer et la barre de recherche déployée), la pilule de fil d’Ariane et la barre d’actions inférieure gauche.
  - Suppression du voile blanc statique inférieur et des séparateurs verticaux superflus en mode Espace de travail afin que les lignes de fichiers défilantes se réfractent directement à travers la capsule flottante Liquid Glass.
  - Affinage du liseré lumineux en verre du bouton principal Flow et de l’indicateur de carte empilée affleurante, déployant en douceur l’action secondaire `Extraire` au survol.
  - Unification des commandes `Ouvrir une archive`, `Créer une archive` et `Réglages` de la fenêtre d’accueil avec Liquid Glass natif.

### Corrigé
- Correction d’un problème où les badges de raccourcis clavier (`⏎` / `Espace`) à l’intérieur de la capsule d’actions inférieure de l’espace de travail s’affichaient en blanc sur blanc au survol.

---

## [0.1.0] - 2026-11-12

### Ajouté
- **Première version open source (GPL-3.0)** :
  - Architecture de moteur d’archives à quatre niveaux associant `NativeZipEngine` (lecteur ZIP pur Swift sans copie), 7-Zip (LZMA2 multithread), `libarchive` système et le montage d’images disque via `hdiutil`.
  - Indexation hiérarchique rapide des entrées sous SQLite (`EntryIndex`) pour parcourir et rechercher instantanément dans les archives volumineuses.
  - Flux de travail à double mode basculant instantanément (`⌥⌘M`) entre l’espace de travail multivue `1040×740` (Icônes, Liste, Colonnes) et le navigateur compact Mini `560×422`.
  - Moteur de recommandation contextuel Flow (installation de paquets d’applications, installation de polices, ouverture directe sécurisée sur liste blanche et extraction en un clic).
  - Zone de dépôt persistante dans la barre des menus (Shelf) pour le glisser-déposer multisource, la navigation en ligne dans les dossiers et archives, ainsi que la compression et l’extraction par lots.
  - Carnet de mots de passe local chiffré en AES-GCM adossé au Trousseau (Keychain) de macOS, au déverrouillage Touch ID et à la correspondance automatique des mots de passe.
  - Extension intégrée de menu contextuel du Finder (`ProZipFinderSync`) et extension d’aperçu Coup d’œil (`ProZipQuickLook`).

[0.1.5]: https://github.com/scoltzero/prozip/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/scoltzero/prozip/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/scoltzero/prozip/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/scoltzero/prozip/compare/v0.1.0...v0.1.2
[0.1.0]: https://github.com/scoltzero/prozip/releases/tag/v0.1.0
