<p align="center">
  <img src="screens/logo.png" alt="macSSH Logo" width="160"/>
</p>

<h1 align="center">macSSH</h1>

<p align="center">
  <strong>Native macOS Manager for SSH / SFTP, FTP / FTPS, SMB, Read-Write Finder Mount, Terminal & Dynamic SOCKS5 Proxy</strong>
</p>

<p align="center">
  <em>Pure Swift & SwiftUI • Universal Binary (Apple Silicon & Intel)</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15.0%2B%20(Sequoia%20%7C%20Tahoe)-black?style=flat-square&logo=apple" alt="macOS 15.0+ (Sequoia | Tahoe)"/>
  <img src="https://img.shields.io/badge/Swift-5.9%2B%20%7C%206.0-orange?style=flat-square&logo=swift" alt="Swift 5.9+ / 6.0"/>
  <img src="https://img.shields.io/badge/Architecture-Universal%20(arm64%20%2B%20x86__64)-purple?style=flat-square" alt="Universal Binary"/>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License MIT"/></a>
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
> It is an ultra-fast, 100% native macOS application engineered with **SwiftUI**, **AppKit**, **SwiftData**, **Network.framework**, **AVKit**, **PDFKit**, **NetFS**, and Apple's **LocalAuthentication (Touch ID)**.
>
> It does **NOT** support Windows or Linux — delivering blazing-fast native Apple performance, zero input latency, and minimal memory footprint.

---

## 🌟 Overview

**macSSH** provides a complete, modern, and native remote workspace for developers, DevOps engineers, and system administrators on macOS:

- **Multi-Protocol Support (SSH, FTP, SMB)**: Manage **SSH/SFTP**, **FTP/FTPS**, and **SMB/CIFS** servers with automatic protocol defaults, matching icons/colors, anonymous/guest auth, and automatic SMB share discovery.
- **Read-Write Native Finder Mount (FTP & SFTP)**: Mount remote FTP/FTPS and SFTP servers directly in **macOS Finder** as Read-Write volumes via an embedded SwiftNIO WebDAV Class 2 loopback bridge — **zero macFUSE, FUSE-T, kexts, or `sudo` required**.
- **High-Speed Dual-Pane File Browser & Multi-Stream FTP**: Two-way native drag & drop (Local ⇄ Remote ⇄ Finder), recursive folder transfers, and configurable **multi-stream FTP transfers (default 10 streams, up to 32)** with byte-range parallel downloads.
- **Built-in Universal File Viewer**: Preview remote text/code, images, PDFs, audio/video (`MP4`/`MOV`/`MP3` via `AVKit`), and binary Hex/ASCII right inside macSSH across SSH, FTP, and SMB.
- **Quick Automation (`Auto Connect` & FTP `Auto Mount`)**: One-click quick-toggle pills at the bottom-right of each connection card (zero page reload), startup launch automation, and automatic FTP Finder mount when clicking Connect.
- **Native OpenSSH Terminal & Dynamic SOCKS5 Proxy**: Zero-latency `xterm-256color` SwiftTerm emulator (60 FPS), 1-click `Terminal.app` launcher, and native `/usr/bin/ssh -D` SOCKS5 tunnels (`127.0.0.1` or LAN `0.0.0.0`) with orphan process protection.
- **Real-Time Internet Monitoring & Menu Bar Mode**: Live `NWPathMonitor` detection, progressive auto-reconnect backoff, macOS banners, and automatic Dock icon hiding when running minimized in the Menu Bar.

---

## ✨ Key Features & Functions

### 🔌 1. Multi-Protocol Connection Manager (`SSH` / `FTP` / `SMB`)
- **Unified Protocol Picker (`SSH | FTP | SMB`)**: Segmented selector in the connection form automatically configures default ports (`22` / `21` / `445`), protocol-matched icons and accent colors, and protocol-specific options.
- **FTP / FTPS Engine**: Powered by macOS `/usr/bin/curl` passing credentials securely via stdin (`--config -`, never exposed in CLI arguments), supporting Unix `ls -l` and Windows/IIS/DOS directory listings plus anonymous login.
- **SMB / CIFS Engine**: Powered by Apple `NetFS.framework` and `/usr/bin/smbutil` with guest login, direct `host/ShareName` support, or automatic SMB disk share discovery at `/`, automatically unmounting cleanly on disconnect.

### 💽 2. Read-Write Mount in Finder (Driver-Free Loopback WebDAV)
- **Full Read-Write Access in Finder**: Mount FTP, FTPS, and SFTP servers directly in **Finder** via an embedded **SwiftNIO WebDAV Class 2** loopback server and `/sbin/mount_webdav -S -o browse` — no third-party kernel extensions, macFUSE, FUSE-T, or `sudo` needed.
- **Clean Server Naming in Finder**: Uses loopback-only `dnssd` (`lo0` → `127.0.0.1`) so Finder Sidebar displays your connection **Name** directly instead of `127.0.0.1` or `.local` suffixes.
- **Smart Streaming & Zero Unwanted Downloads**: Directory browsing uses cached listings (`PROPFIND`) + virtual QuickLook/Spotlight/FSEvents sentinels (`.ql_disablethumbnails`, `.metadata_never_index`, `.fseventsd/no_log`) and Apple metadata shadow storage (`._*`, `.DS_Store`, `.TemporaryItems`) so opening folders in Finder never triggers full-file downloads. `GET` requests stream byte-ranges on demand (`curl --range` / Citadel chunked reads) and terminate immediately if canceled.
- **3-Tier Automatic Unmount**: Unmounts cleanly on Disconnect, Finder Eject (`⏏`), App Quit (`⌘Q`), crash (`-S` instant kernel auto-unmount + `atexit`), and cleans up orphan mounts at next launch.

### ⚡ 3. Quick Settings (`Auto Connect` & `Auto Mount`) & Instant UI
- **Bottom-Right Card Quick Toggles**:
  - **`Auto Connect`** (all protocols): Automatically establishes the session when macSSH launches or when opening a configuration file (`⌘O`).
  - **`Auto Mount`** (**FTP only**): Automatically mounts the FTP server into Finder on launch/config load **and** automatically mounts whenever you manually click **Connect**.
- **Zero-Reload In-Place Updates**: Toggling `Auto Connect`, `Auto Mount`, `Saved`, or `SOCKS5` updates the connection row in place immediately without refreshing or flashing the connection list.
- **Touch ID Lock Aware**: Automatically waits until Touch ID / macSSH App Lock is unlocked before running startup automation.

### 🌐 4. Native OpenSSH SOCKS5 Proxy & Process Lifecycle
- **Headless Native `/usr/bin/ssh -D` Tunnel**: Runs dynamic SOCKS5 port forwarding through native OpenSSH (`forkpty` + direct FD credential feeding, never exposed in `ps aux`), resilient across macOS Sleep/Wake and App Nap.
- **Localhost & LAN Sharing**: Bind to `127.0.0.1` or `0.0.0.0` (with auto-detected LAN IP endpoint display) and toggle live on any SSH row.
- **Smart Port Conflict Protection**: Detects `Address already in use`, turns off conflicting proxy gracefully, and alerts with a 5-second toast.
- **Orphan-Free Lifecycle (`NativeProcessRegistry`)**: Tracks child processes with `atexit`, C signal handlers, and startup orphan cleanup so ports are never left dangling after crashes.

### 🚀 5. Dual-Pane Browser & Multi-Stream FTP Transfers
- **Dual-Pane Drag & Drop**: Local (macOS) on the left, Remote (Server) on the right, with two-way drag & drop between panes and drag-out directly to **macOS Finder** (`NSFilePromiseProvider`).
- **Configurable Multi-Stream FTP (`1–32` Streams, Default `10`)**:
  - Adjust global streams in **Settings**, per-connection overrides in the connection sheet, or live on the **Transfer Queue** bar (`10 streams` pill with `1 / 5 / 10 / 20 / 32` presets).
  - Concurrent multi-file & recursive folder upload/download with batch duplicate prompts (`Replace`, `Replace All`, `Skip`, `Cancel`), multi-part byte-range parallel downloads (`>= 4 MB`), and live upload speed/ETA tracking.
- **Smooth Queue Scheduling**: Off-main-thread directory scanning, batched FTP `*MKD` creation, bounded worker scheduler (`pumpTransferQueue`), throttled UI progress ticks (`120ms`), direct path bar (`⌘L` / `⇧⌘G`), and multi-file batch delete.

### 👁️ 6. Built-in Universal File Viewer & "Edit With" Auto-Sync
- **Universal File Viewer (SSH, FTP, SMB)**: Preview files via toolbar (`eye.fill`), context menu, or double-click across 5 native viewers:
  1. **Text / Code / Config / Log**: Monospaced viewer with line numbers, search, Copy, and 1-click **"Open in Editor"**.
  2. **Image Viewer**: Interactive zoom controls (`-`, `100%`, `+`, `Reset`) and native resolution readout.
  3. **PDF Viewer**: Smooth scrolling & zoom powered by Apple `PDFKit`.
  4. **Audio & Video Player**: Native `AVKit` playback for `.mp4`, `.mov`, `.mp3`, `.wav`, `.m4a`, etc., with `Open Externally` fallback for unsupported codecs.
  5. **Binary Hex & ASCII Inspector**: Inspects first 4 KB in 16-byte rows + `Open Externally`.
- **"Edit With" & Save Auto-Upload**: Open remote files in VS Code, Xcode, Sublime Text, TextEdit, etc.; macSSH monitors saves (`⌘S`, 2s polling) and auto-uploads changes back with Transfer Queue tracking. All temp preview files clean up automatically when closing.

### 📊 7. Enhanced Transfer Queue & Resizable Activity Logs
- **Queue Counters, Filters & Batch Retry**:
  - Clickable **Succeeded (`✓ N`)** and **Failed (`✕ M`)** header pills, status filter chips (`All`, `Active`, `Succeeded`, `Failed`, `Cancelled`), live filename filter, and **Retry** / **Retry Failed** buttons on both Upload & Download tabs.
- **Live Activity Log Console**:
  - Collapsible bottom console (`⌘⇧L`) capped at the newest 200 entries (zero-allocation release logger macros), filterable by severity & category (`Network`, `SOCKS5`, `SFTP`, `Terminal`, `Auth`, `Database`, `App`) with clipboard copy.
- **Native Resize Handles**: Both bottom panels feature smooth height dragging with dynamic `↕︎` resize cursors.

### 🌐 8. Real-Time Internet Monitor & Progressive Reconnect
- **`NWPathMonitor` Connectivity Watcher**: Instantly updates row badges (`No Internet` pulsing red), server icons, and Menu Bar indicators (`🟢` → `🔴`) upon Wi-Fi/Ethernet outage, displaying an in-app banner plus an auto-dismissing (5s) macOS notification.
- **Progressive Retry Backoff**: When internet returns, macSSH cleanly tears down stale SSH/SOCKS5 sessions & refreshes Finder mounts, then retries reconnection immediately → `5s` → `10s` (resetting automatically if connectivity drops mid-retry).

### 🎨 9. Native macOS Ergonomics, Menu Bar & Security
- **Light / Dark / System Appearance**: Instant **1-click Dark ↔ Light toggle** icon on the toolbar (`sun.max.fill` / `moon.fill`), synced via `View → Appearance` and `Settings → General`.
- **Full macOS Top Menu Bar & Empty-Area Context Menus**: Complete `File` (`Save Configuration`, `New Configuration`, `Export`/`Import`), `Connection` (Connect, File Browser, Mount/Open/Unmount Finder, Terminal), and `View` menus; right-click empty space in Sidebar (**New Folder**) or Connection List (**New Connection**).
- **Menu Bar Background Mode & Auto-Hide Dock**: Closing the main window hides macSSH from the Dock (`accessory` policy) while keeping SSH sessions, SOCKS5 tunnels, and Finder mounts active in the Menu Bar.
- **Standalone Encrypted Config & Touch ID Lock**: JSON configs (`⌘S`, `⇧⌘S`, `⌘O`) with auto-reload last file, optional hardware-bound **AES-256-GCM** encrypted passwords inside configs, and Apple **Touch ID** app lock.
- **6-Language Localization**: Instant switching across **English**, **Tiếng Việt**, **简体中文**, **繁體中文**, **Русский**, and **Français**.

---

## 📸 Screenshots

| Connection Manager & Sidebar | Context Menu & Server Actions |
|:---:|:---:|
| ![Connection Manager](screens/screen-1.png) | ![Context Menu](screens/screen-2.png) |
| *2-column layout, folders, quick settings & status badges* | *Right-click menu: Finder Mount, SOCKS5, Terminal, File Browser* |

| Dual-Pane Browser & Transfer Queue | Integrated SSH Terminal |
|:---:|:---:|
| ![File Browser](screens/screen-3.png) | ![SSH Terminal](screens/screen-4.png) |
| *Two-way drag & drop, direct path bar, speed & ETA* | *Zero-latency xterm-256color terminal emulator* |

---

## 💽 Installation & Setup

### System Requirements
- **macOS**: 15.0 or later (Sequoia | Tahoe).
- **Architecture**: Universal 2 (Apple Silicon M1–M4 & Intel x86_64).

### Option 1: Download Pre-built DMG (Recommended)
1. Go to the [Releases](https://github.com/devduong/macSSH/releases) page.
2. Download the latest `macSSH_Universal_x.x.x.dmg`.
3. Open the DMG and drag **macSSH** to your **Applications** folder.

> [!IMPORTANT]
> **First-Time Launch (Bypass macOS Gatekeeper):**
> If macOS displays *"macSSH can't be opened because Apple cannot check it for malicious software"*:
> 1. Open **System Settings** -> **Privacy & Security**.
> 2. Scroll down to the **Security** section.
> 3. Click **"Open Anyway"** next to the macSSH notice.
> 4. Enter your Mac password / Touch ID to confirm.

---

### Option 2: Build from Source

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

3. **Build the Application**:
   ```bash
   xcodebuild -project macSSH.xcodeproj -scheme macSSH -configuration Release build
   ```
   *Or select the `macSSH` scheme in Xcode and press `Cmd + B`.*

4. **Run the built application**:
   ```bash
   open $(xcodebuild -project macSSH.xcodeproj -scheme macSSH -configuration Release -showBuildSettings | grep -m 1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')/macSSH.app
   ```
   *Or press `Cmd + R` to run directly in Xcode.*

---

## 🏗️ Project Architecture

```
macSSH/
├── App/                          # App entry point, AppDelegate lifecycle, MenuBarExtra, DI
│   ├── MacSSHApp.swift
│   └── DependencyContainer.swift
├── Core/                         # Version metadata, Errors, Appearance, NetworkMonitor, L10N
│   ├── AppVersion.swift
│   ├── Errors/
│   ├── Extensions/
│   ├── Localization/             # Key-based L10N (EN, VI, FR, RU, ZH-Hans, ZH-Hant)
│   └── Utilities/                # NetworkMonitor, FTPTransferSettings, AppearanceManager, NativeProcessRegistry
├── Domain/                       # Models & Repository Protocols
│   ├── Models/                   # Connection, ConnectionType (SSH/FTP/SMB), RemoteFile, TransferProgress
│   └── RepositoryProtocols/
├── Data/                         # Protocol Engines, WebDAV Loopback & Persistence
│   ├── SFTP/                     # SFTPSession (Citadel), FTPSession (curl), SMBSession (NetFS)
│   ├── WebDAV/                   # WebDAVHTTPServer (SwiftNIO) & WebDAVBridge (Class 2 Read-Write)
│   ├── Terminal/                 # NativeTerminalSession (forkpty + /usr/bin/ssh)
│   ├── Tunnel/                   # NativeSocksTunnel (headless ssh -D dynamic forwarding)
│   ├── SwiftData/                # DataStore, Entities, Mappers
│   └── Repositories/
├── Features/                     # SwiftUI + AppKit Views & ViewModels
│   ├── Connections/              # SplitView, ConnectionRowView (Quick Settings), Logs Console
│   ├── Browser/                  # DualPaneFileBrowser, FileViewerSheet, TransferQueueBottomPanel
│   ├── Editor/                   # Built-in File Editor
│   ├── FileInfo/                 # Remote File Inspector & Chmod
│   ├── MenuBar/                  # MenuBarContentView
│   ├── Terminal/                 # SwiftTerm xterm-256color emulator
│   └── Settings/                 # SettingsView, DonateSheetView, AboutSheetView
└── Services/                     # App Services
    ├── FinderMountManager.swift  # mount_webdav -S lifecycle, lo0 Bonjour naming, 3-tier unmount
    ├── StartupAutomationService.swift # Auto Connect & FTP Auto Mount after unlock / config load
    ├── ConnectionSessionManager.swift # Session & SOCKS5 lifecycle + progressive auto-reconnect
    ├── ConfigurationService.swift # JSON Config Save/Load + AES-256-GCM credential restore
    ├── ExternalEditorService.swift # Edit With external app & auto-upload on save
    └── TerminalLauncherService.swift # Launch native macOS Terminal.app via AppleScript
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
- 🚀 [Citadel](https://github.com/Orlandos-nl/Citadel) by Joannis Orlandos & [SwiftNIO](https://github.com/apple/swift-nio) / [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh) — Core SSH, SFTP, and WebDAV HTTP loopback networking.
- 💻 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) by Miguel de Icaza — High-performance terminal emulation for macOS.
- 🎨 [SF Symbols](https://developer.apple.com/sf-symbols/) by Apple — Native macOS system typography and iconography.

---

## 📄 License

This project is open-source under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  Crafted with ❤️ for the macOS community.
</p>
