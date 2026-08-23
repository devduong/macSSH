<p align="center">
  <img src="screens/logo.png" alt="macSSH Logo" width="160"/>
</p>

<h1 align="center">macSSH</h1>

<p align="center">
  <strong>Native macOS Manager for SSH, SFTP, Terminal & Dynamic SOCKS5 Proxy</strong>
</p>

<p align="center">
  <em>Pure Swift & SwiftUI • Universal Binary (Apple Silicon & Intel)</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15.0%2B%20(Sequoia%20%7C%20Tahoe)-black?style=flat-square&logo=apple" alt="macOS 15.0+ (Sequoia | Tahoe)"/>
  <img src="https://img.shields.io/badge/Swift-5.9%2B%20%7C%206.0-orange?style=flat-square&logo=swift" alt="Swift 5.9+ / 6.0"/>
  <img src="https://img.shields.io/badge/Architecture-Universal%20(arm64%20%2B%20x86__64)-purple?style=flat-square" alt="Universal Binary"/>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License MIT"/></a>
  <a href="https://github.com/devduong/macSSH/releases"><img src="https://img.shields.io/badge/Version-0.2.7-007acc?style=flat-square" alt="Version"/></a>
</p>

---

<p align="center">
  🌐 <strong>Languages / 多语言 / Ngôn ngữ / Языки / Langues</strong>
</p>

<p align="center">
  <strong>English</strong> •
  <a href="Readme/README_VI.md">Tiếng Việt</a> •
  <a href="Readme/README_ZH_CN.md">简体中文</a> •
  <a href="Readme/README_ZH_TW.md">繁體中文</a> •
  <a href="Readme/README_RU.md">Русский</a> •
  <a href="Readme/README_FR.md">Français</a>
</p>

---

## ⚠️ Important: macOS Only

> [!IMPORTANT]
> **macSSH is built specifically for Apple macOS.**
> It is an ultra-fast, 100% native macOS application engineered with **SwiftUI**, **AppKit**, **SwiftData**, and Apple's **LocalAuthentication (Touch ID)** frameworks.
> 
> It does **NOT** support Windows or Linux — delivering blazing-fast native Apple performance, zero latency, and minimal memory footprint.

---

## 🌟 Overview

**macSSH** provides a complete, modern, and native solution for developers, DevOps engineers, and system administrators managing remote infrastructure on macOS:

- **Dual-Pane SFTP File Browser**: Intuitive two-way drag & drop between Local and Remote panes, and direct drag & drop to macOS Finder.
- **High-Performance SSH Terminal**: Full `xterm-256color` terminal emulator powered by SwiftTerm (60 FPS), with OpenSSH-standard PTY zero-latency direct feed, plus 1-click launch into native macOS `Terminal.app`.
- **Dynamic SOCKS5 Proxy via SSH Tunnel**: Built-in SOCKS5 proxy server routed through SSH tunnels. Supports binding to Localhost (`127.0.0.1`) or sharing across the local network (`0.0.0.0`) with one-click toggle and automatic port collision recovery.
- **External Editor "Open With" & Auto-Sync**: Open remote files in your favorite macOS apps (VS Code, TextEdit, Xcode, Sublime Text, etc.) and automatically upload changes directly to the server upon pressing Save (`⌘S`).
- **Menu Bar Status & Background Execution**: Runs smoothly in the macOS Menu Bar, keeping SSH tunnels and SOCKS5 proxies active even when all application windows are closed.
- **Secure & Standalone Configuration**: Export/Import JSON configs, automatically remembers the last opened configuration file, Touch ID biometric app lock, and AES-256-GCM encrypted credential storage.

---

## ✨ Key Features & Functions

### 🌐 1. Dynamic SOCKS5 Proxy (SSH Tunnel)
- **Automatic SSH Tunnel Proxy**: Opens a local SOCKS5 proxy server directly through the active SSH session.
- **Localhost & LAN Sharing**: Bind to `127.0.0.1` (local Mac only) or `0.0.0.0` (share proxy connection with devices across your local network, with auto-detected LAN IP display).
- **Quick Toggle Badge**: Purple SOCKS5 badge on each server row lets you toggle proxy status on/off instantly without opening settings.
- **Smart Port Conflict Handling**: If a configured SOCKS5 port is already in use (`Address already in use`), macSSH automatically disables proxy gracefully and displays a 5-second glassmorphic toast notification without interrupting your main SSH session.

### 📂 2. Dual-Pane SFTP Browser & Two-Way Drag & Drop
- **Dual-Pane Layout**: Side-by-side view with Local Pane (macOS) on the left and Remote Pane (Server) on the right.
- **Two-Way Native Drag & Drop**:
  - Drag files/folders from Local to Remote to upload.
  - Drag files/folders from Remote to Local (or into specific subdirectories) to download instantly.
  - Drag remote files directly out into **macOS Finder** via `NSFilePromiseProvider`.
- **Recursive Folder Downloads**: Recursively downloads entire folder hierarchies and nested subdirectories automatically.
- **Direct Path TextField Bar**: Quickly type or paste absolute paths (`/var/www`, `~/.config`) with keyboard shortcuts `⌘L` or `⇧⌘G`.
- **Safe Overwrite Confirmation**: Native `NSAlert` modal to Confirm Replace or Cancel if destination files already exist.
- **Clean Table Experience**: No awkward horizontal scrollbars; smart column autosizing and multi-selection batch deletion support.

### 📝 3. "Open With" External Editor & Auto-Sync on Save
- **Open Remote Files in macOS Apps**: Right-click context menu with `Open With Default App` and `Open With…` (automatically lists installed editors like VS Code, Xcode, Sublime Text, TextEdit, Preview, etc.).
- **Automatic Sync upon `⌘S`**: Monitored via a 2-second Polling Timer. Whenever you save (`⌘S`) in your external editor, macSSH detects changes and instantly uploads the file back to the remote server with live console logging.

### 💻 4. Comprehensive SSH Terminal & Zero-Latency Input
- **SwiftTerm Terminal Emulator**: Native 60 FPS terminal emulator supporting `xterm-256color` and full POSIX terminal capabilities.
- **Zero-Latency Direct Feed**: Standardized OpenSSH PTY modes (`.ECHO`, `.ICANON`, POSIX control keys) with direct main-thread byte feeding, eliminating keyboard lag or buffering delays.
- **Launch in Native macOS Terminal**: One-click **"Open in macOS Terminal"** button and context menu item launches the session directly inside macOS `Terminal.app` via AppleScript.
- **Automatic Password Retry Sheet**: Automatically detects SSH authentication errors (`AuthenticationFailed`, `CitadelError.unauthorized`) and presents a clean prompt sheet to re-enter credentials.

### 📊 5. Transfer Queue & Real-Time Log Console
- **3-Tab Bottom Panel in File Browser**:
  - 📤 **Upload Queue**: Track uploading files with progress percentage, bytes transferred/total, **real-time transfer speed (MB/s, KB/s)**, **estimated time remaining (ETA)**, and Cancel controls.
  - 📥 **Download Queue**: Real-time progress, speed, and ETA monitoring for downloads.
  - 📜 **Log Console**: Live SFTP command activity stream with timestamps `[HH:mm:ss]`, color-coded levels (`[INFO]`, `[SUCCESS]`, `[WARN]`, `[ERROR]`).
- **In-Memory & Clean Lifecycle**: Queue and log data remain strictly in RAM during the active session and are released cleanly when the window is closed.

### 🗂️ 6. Streamlined 2-Column SplitView & Quick Actions
- **2-Column Layout**: Clean NavigationSplitView featuring a Sidebar (Folders, Settings, Donate, About) and Connection List.
- **Cross-Column Drag & Drop**: Drag server items from the list and drop them directly onto folders in the Sidebar.
- **Double-Click Auto-Connect**: Double-click any server row to connect and open the File Browser immediately.
- **Instant Online Status Sync**: Green dot status indicator updates in real-time as soon as a connection is established.
- **Quick Action Buttons**: Always-visible buttons for 📁 Open File Browser and `>_` Open Terminal on each connection row.

### 💾 7. Standalone Configuration & Biometric Security
- **JSON Configuration Management**: Save (`⌘S`), Save As (`⇧⌘S`), Open (`⌘O`), or Create New Configuration (`⌘⌥N`).
- **Auto-Load Last File**: Remembers the active configuration file and reloads it on launch.
- **Unsaved Changes Warning**: `NSAlert` prompt with 3 options (Save / Don't Save / Cancel) when quitting with unsaved edits.
- **Encrypted Password Storage (AES-256-GCM)**: Passwords can be encrypted and saved inside configuration files if enabled, removing hard dependencies on macOS Keychain.
- **Touch ID App Lock**: Lock and unlock macSSH using Apple Touch ID or macOS system password.

### 🌐 8. Multi-Language System (Key-Based L10N)
- Built-in multi-language support with automatic English fallback:
  - 🇬🇧 **English** (Default Fallback)
  - 🇻🇳 **Tiếng Việt** (Vietnamese)
  - 🇨🇳 **简体中文** (Simplified Chinese)
  - 🇹🇼 **繁體中文** (Traditional Chinese)
  - 🇷🇺 **Русский** (Russian)
  - 🇫🇷 **Français** (French)
- Switch languages on the fly in Settings with immediate UI updates.

---

## 📸 Screenshots

| Connection Manager & Sidebar | Context Menu & Server Actions |
|:---:|:---:|
| ![Connection Manager](screens/screen-1.png) | ![Context Menu](screens/screen-2.png) |
| *2-column layout, folder categorization, quick connect* | *Right-click menu: SOCKS5 proxy, Terminal, SFTP* |

| Dual-Pane SFTP Browser & Transfer Queue | Integrated SSH Terminal |
|:---:|:---:|
| ![File Browser](screens/screen-3.png) | ![SSH Terminal](screens/screen-4.png) |
| *Two-way drag & drop, direct path bar, real-time speed & ETA* | *Zero-latency xterm-256color terminal emulator* |

---

## 💽 Installation & Setup

### System Requirements
- **macOS**: 15.0+ (Sequoia | Tahoe).
- **Architecture**: Universal 2 (Optimized for both **Apple Silicon M1/M2/M3/M4** and **Intel x86_64**).

### 1. Download DMG
Download the latest `macSSH_Universal_x.x.x.dmg` from [GitHub Releases](https://github.com/devduong/macSSH/releases).

### 2. Install App
Open the DMG and drag **macSSH.app** into your **Applications** (`/Applications`) folder.

### 3. First Launch & macOS Gatekeeper Bypass

> [!WARNING]
> **Warning**  
> Because macSSH is a free open-source project and is not signed with a paid Apple Developer certificate, macOS Gatekeeper may show a warning: *"macSSH cannot be opened because the developer cannot be verified"* or *"macOS cannot verify that this app is free from malware"*.

To open the app:
1. Open **System Settings** on your Mac.
2. Go to **Privacy & Security**.
3. Scroll down to the **Security** section.
4. Click the **"Open Anyway"** button next to the notification that macSSH was blocked.
5. In the confirmation dialog, click **"Open"** and enter your Mac password or use Touch ID.

*(Alternative: Right-click / Control-click `macSSH.app` in Finder -> select **Open** -> click **Open**).*

---

### Building from Source

#### Prerequisites
- **Xcode**: 16.0 or later.
- **macOS SDK**: 15.0 or later.
- **Swift**: 5.9+.

#### Build Steps

1. **Clone the repository**:
   ```bash
   git clone https://github.com/devduong/macSSH.git
   cd macSSH
   ```

2. **Open the project in Xcode**:
   ```bash
   open macSSH.xcodeproj
   ```

3. **Build & Package the Universal DMG**:
   ```bash
   ./create-dmg.sh
   ```
   *The script automatically compiles Release Universal binaries (`arm64` + `x86_64`), applies ad-hoc codesign, and packages the final distributable DMG at `build/macSSH.app`.*

4. **Run the built application**:
   ```bash
   open build/macSSH.app
   ```

---

## 🏗️ Project Architecture

```
macSSH/
├── App/                          # App entry point, AppDelegate, MenuBarExtra
│   ├── MacSSHApp.swift
│   └── DependencyContainer.swift
├── Core/                         # Core App Settings, Utilities & Localization
│   ├── AppVersion.swift          # Centralized version metadata
│   ├── Errors/                   # AppError & Error handling
│   └── Localization/             # L10N System (L10n_EN, L10n_VI, L10n_FR,...)
├── Domain/                       # Business Logic & Codable Models
│   ├── Models/
│   │   ├── Connection.swift      # Connection model (SOCKS5, Port, SSH Auth)
│   │   ├── TransferProgress.swift# Transfer model (Speed MB/s, ETA, %)
│   │   ├── SFTPLogEntry.swift    # SFTP Console Log model
│   │   ├── RemoteFile.swift
│   │   └── Folder.swift
├── Data/                         # Networking & Persistence
│   ├── SwiftData/                # DataStore & Entities
│   ├── SFTP/                     # Citadel SFTP session & Directory handling
│   ├── Terminal/                 # TerminalSession (OpenSSH PTY modes, direct feed)
│   └── Tunnel/                   # SOCKS5 Proxy Server (LAN 0.0.0.0 & Localhost)
├── Features/                     # UI Views & ViewModels (SwiftUI + AppKit)
│   ├── Connections/              # 2-Column SplitView, Sidebar, ConnectionListColumn
│   ├── Browser/                  # DualPaneFileBrowser, Local/Remote TableView, TransferQueue
│   ├── MenuBar/                  # MenuBarContentView (System Menu Bar Extra)
│   ├── Terminal/                 # SwiftTermView, TerminalView, TerminalViewModel
│   └── Settings/                 # SettingsView, DonateSheetView, AboutSheetView
└── Services/                     # Core App Services
    ├── ExternalEditorService.swift # External editor & auto-upload on save (Polling 2s)
    ├── TerminalLauncherService.swift # Launch native macOS Terminal.app via AppleScript
    ├── ConfigurationService.swift # JSON Config management, Auto-load, Safe New Config
    └── ConnectionSessionManager.swift # Global SSH/SFTP/Proxy session & realtime status
```

---

## ☕ Support & Donation (Donate)

**macSSH** is a free and open-source project created to deliver the best remote management experience on macOS. If macSSH saves you time or enhances your workflow, consider supporting development! ❤️

### 1. Support via Ko-fi & GitHub
- ☕ **Ko-fi**: [https://ko-fi.com/X4P324ZPZ3](https://ko-fi.com/X4P324ZPZ3)
- ⭐ **Star on GitHub**: [devduong/macSSH](https://github.com/devduong/macSSH)

### 2. Crypto Donation (BEP20 / BSC)
You can send any **BNB Smart Chain (BEP20)** token (*USDT, BNB, BUSD, USDC, etc.*) to the wallet address below:

- **Network**: `BEP20 (BSC – Binance Smart Chain)`
- **Wallet Address**:
  ```text
  0xe26c0DC422EF744816Ca3B2d210e6214fdC4e18E
  ```

---

## 🙏 Acknowledgments & Credits

- 🌟 **Special thanks to [macnev2013](https://github.com/macnev2013)** — The author of `macSCP` and `anySCP`. Thank you so much for the brilliant initial design ideas and foundation that inspired the creation and evolution of **macSSH**.
- 🚀 [Citadel](https://github.com/Orlandos-nl/Citadel) by Joannis Orlandos & [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh) by Apple — Core SSH & SFTP protocol foundation.
- 💻 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) by Miguel de Icaza — High-performance terminal emulation for macOS.
- 🎨 [SF Symbols](https://developer.apple.com/sf-symbols/) by Apple — Native macOS system typography and iconography.

---

## 📄 License

This project is open-source under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  Crafted with ❤️ for the macOS community.
</p>
