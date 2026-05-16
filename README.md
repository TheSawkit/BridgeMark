# BridgeMark

[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=flat&logo=swift&logoColor=white)](https://swift.org/)
[![macOS](https://img.shields.io/badge/macOS-13%2B-000000?style=flat&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![SPM](https://img.shields.io/badge/SPM-compatible-F05138?style=flat)](https://swift.org/package-manager/)
[![Download](https://img.shields.io/badge/download-latest-blue?style=flat)](https://github.com/TheSawkit/BridgeMark/releases/latest)

> **Your Safari bookmarks, everywhere.**
> Export your entire bookmark bar to any Chromium browser in one click — Safari is never touched.

**[🇬🇧 English](#-english) | [🇫🇷 Français](#-français)**

---

## 🇬🇧 English

### ✨ Features

|      | Feature                          | Description                                                                                     |
| ---- | -------------------------------- | ----------------------------------------------------------------------------------------------- |
| 🔀   | **Merge mode**             | Adds Safari bookmarks without touching what already exists. Folders merged recursively by name. |
| 🔄   | **Overwrite mode**         | Replaces the full bookmark bar with a confirmation dialog and a timestamped backup.             |
| 💾   | **Auto-backup**            | Every write creates a `.backup-YYYYMMDD-HHmmss` copy. Last 5 kept automatically.              |
| 🛡️ | **Open browser detection** | Refuses to write if the target browser is running — prevents file corruption.                  |
| 🔔   | **System notifications**   | Native macOS notification on sync success or error.                                             |
| 🌍   | **FR / EN**                | Fully localized in French and English via `Localizable.xcstrings`.                            |

### 🛠️ Supported browsers

Brave · Google Chrome · Microsoft Edge · Opera · Vivaldi · Arc

### 🚀 Quick Start

**Prerequisites:** macOS 13+ and Xcode 15+ (or Swift 6 toolchain)

```bash
git clone https://github.com/TheSawkit/BridgeMark.git
cd BridgeMark
swift run BridgeMark
```

> ⚠️ BridgeMark needs **Full Disk Access** to read Safari's bookmarks.
> System Settings → Privacy & Security → Full Disk Access → add BridgeMark.
> The app shows a direct link to this panel if access is denied at runtime.

### 📁 Project Structure

```text
BridgeMark/
├── Sources/BridgeMark/
│   ├── BridgeMarkApp.swift        # App entry point, ContentView, SyncViewModel
│   ├── SyncEngine.swift           # BrowserProfile, BookmarkNode, SyncEngine
│   └── Localizable.xcstrings      # FR (source) + EN strings
├── Package.swift                  # SPM manifest (swift-tools-version: 6.0)
└── BridgeMark.entitlements        # com.apple.security.files.all
```

### 📦 Commands

| Command                  | Description      |
| :----------------------- | :--------------- |
| `swift build`          | Compile          |
| `swift run BridgeMark` | Compile + launch |
| `open Package.swift`   | Open in Xcode    |

### 🚢 Distribution

Requires Hardened Runtime + Apple notarization:

```bash
codesign --deep --force --options runtime \
  --entitlements BridgeMark.entitlements \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  .build/release/BridgeMark

xcrun notarytool submit BridgeMark.zip \
  --apple-id your@email.com --team-id TEAMID \
  --password "@keychain:AC_PASSWORD" --wait
```

---

## 🇫🇷 Français

### ✨ Fonctionnalités

|      | Fonctionnalité                        | Description                                                                               |
| ---- | -------------------------------------- | ----------------------------------------------------------------------------------------- |
| 🔀   | **Mode Fusion**                  | Ajoute les favoris Safari sans toucher à l'existant. Dossiers fusionnés récursivement. |
| 🔄   | **Mode Écrasement**             | Remplace toute la barre de favoris avec confirmation et backup horodaté automatique.     |
| 💾   | **Backup auto**                  | Chaque écriture crée un `.backup-YYYYMMDD-HHmmss`. Les 5 derniers sont conservés.    |
| 🛡️ | **Détection navigateur ouvert** | Refuse d'écrire si le navigateur cible tourne — évite la corruption de fichier.        |
| 🔔   | **Notifications système**       | Notification macOS native après chaque sync, en succès ou en erreur.                    |
| 🌍   | **FR / EN**                      | Entièrement localisé via `Localizable.xcstrings`.                                     |

### 🛠️ Navigateurs supportés

Brave · Google Chrome · Microsoft Edge · Opera · Vivaldi · Arc

### 🚀 Installation rapide

**Prérequis :** macOS 13+ et Xcode 15+ (ou toolchain Swift 6)

```bash
git clone https://github.com/TheSawkit/BridgeMark.git
cd BridgeMark
swift run BridgeMark
```

> ⚠️ BridgeMark a besoin de l'**Accès complet au disque** pour lire les favoris Safari.
> Réglages Système → Confidentialité → Accès complet au disque → ajouter BridgeMark.
> En cas de refus au runtime, l'app affiche un lien direct vers ce panneau.

### 📦 Commandes

| Commande                 | Description       |
| :----------------------- | :---------------- |
| `swift build`          | Compiler          |
| `swift run BridgeMark` | Compiler + lancer |
| `open Package.swift`   | Ouvrir dans Xcode |

---

Built with ❤️ by [SAWKIT](https://github.com/TheSawkit)
