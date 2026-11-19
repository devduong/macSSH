<p align="center">
  <img src="../screens/logo.png" alt="macSSH Logo" width="160"/>
</p>

<h1 align="center">macSSH</h1>

<p align="center">
  <strong>專為 macOS 打造的原生 SSH / FTP / SMB 伺服器管理、Finder 讀寫掛載、終端機模擬器與動態 SOCKS5 代理工具</strong>
</p>

<p align="center">
  <em>純 Swift & SwiftUI 開發 • 通用二進位架構 (Apple 晶片 & Intel)</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15.0%2B%20(Sequoia%20%7C%20Tahoe)-black?style=flat-square&logo=apple" alt="macOS 15.0+ (Sequoia | Tahoe)"/>
  <img src="https://img.shields.io/badge/Swift-5.9%2B%20%7C%206.0-orange?style=flat-square&logo=swift" alt="Swift 5.9+ / 6.0"/>
  <img src="https://img.shields.io/badge/Architecture-Universal%20(arm64%20%2B%20x86__64)-purple?style=flat-square" alt="Universal Binary"/>
  <a href="../LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License MIT"/></a>
</p>

---

<p align="center">
  🌐 <strong>Languages / 多语言 / Ngôn ngữ / Языки / Langues</strong>
</p>

<p align="center">
  <a href="../README.md">English</a> •
  <a href="README_VI.md">Tiếng Việt</a> •
  <a href="README_ZH_CN.md">简体中文</a> •
  <strong>繁體中文</strong> •
  <a href="README_RU.md">Русский</a> •
  <a href="README_FR.md">Français</a>
</p>

---

## ⚠️ 重要說明：僅支援 macOS (macOS Only)

> [!IMPORTANT]
> **macSSH 是專門為 Apple macOS 平台量身打造的原生應用程式。**
> 100% 採用 **SwiftUI**、**AppKit**、**SwiftData**、**Network.framework**、**AVKit**、**PDFKit**、**NetFS** 以及 Apple 原生 **LocalAuthentication (Touch ID)** 框架開發。
>
> 本應用程式**不支援** Windows 或 Linux 系統，具有極致的原生反應速度、零按鍵延遲以及極低的記憶體佔用。

---

## 🌟 專案概述

**macSSH** 為在 Mac 上管理遠端伺服器的開發者、DevOps 與系統管理員提供了一站式原生解決方案：

- **多協定支援 (`SSH`、`FTP`、`SMB`)**：統一管理 **SSH/SFTP**、**FTP/FTPS** 與 **SMB/CIFS** 伺服器，自動套用預設連接埠與專屬協定圖示／配色，支援匿名／訪客登入及自動 SMB 共用資料夾探索。
- **Finder 原生讀寫掛載（FTP & SFTP）**：透過內建 **SwiftNIO WebDAV Class 2** 迴路橋接與 `/sbin/mount_webdav -S`，直接在 **macOS Finder** 以讀寫模式掛載遠端目錄 — **無需 macFUSE、FUSE-T 或 `sudo`**。
- **雙欄檔案管理員 & 多執行緒 FTP 傳輸**：本機 ⇄ 遠端 ⇄ Finder 雙向原生拖放、遞迴資料夾傳輸，以及可自訂的 **多執行緒 FTP 傳輸（預設 10 執行緒，支援 1–32）** 與大檔案分段並行下載。
- **內建通用檔案檢視器**：直接於應用程式內預覽 SSH、FTP 與 SMB 伺服器的純文字/程式碼、圖片、PDF、音訊/視訊 (`AVKit`) 及二進位 Hex/ASCII 檢視。
- **快速設定 (`自動連線` 與 FTP `自動掛載`)**：連線項目右下角提供免重新載入的即時開關，支援啟動 / 開啟設定檔時自動執行，以及點擊 Connect 連線 FTP 時自動掛載。
- **原生 OpenSSH 終端機與 SOCKS5 代理**：60 FPS `xterm-256color` 終端機、一鍵開啟 macOS `Terminal.app`、穩定的 `/usr/bin/ssh -D` 代理通道及 `NativeProcessRegistry` 防孤兒程序管理。
- **即時網路監控、自動重連與選單列背景執行**：`NWPathMonitor` 斷網偵測與漸進重連、關閉全部視窗時自動隱藏 Dock 圖示常駐選單列。

---

## ✨ 核心功能與特色

### 🔌 1. 多協定伺服器管理 (`SSH` / `FTP` / `SMB`)
- **協定切換器 (`SSH | FTP | SMB`)**：新增或編輯連線時自動套用預設連接埠（`22` / `21` / `445`）與對應圖示／配色。
- **FTP / FTPS 引擎**：採用系統 `/usr/bin/curl`，憑證經由 stdin 安全傳遞（不暴露於命令列參數），相容 Unix 與 Windows/IIS 清單格式，支援匿名登入。
- **SMB / CIFS 引擎**：整合 Apple `NetFS.framework` 與 `/usr/bin/smbutil`，支援直接連線 `host/ShareName` 或自動掃描伺服器根目錄共用資料夾，斷線時自動卸載清理。

### 💽 2. 免驅動讀寫掛載至 Finder (Loopback WebDAV)
- **原生讀寫體驗**：內建 **SwiftNIO WebDAV Class 2** 服務與 `/sbin/mount_webdav -S -o browse`，直接在 Finder 瀏覽、複製、編輯與刪除遠端 FTP/SFTP 檔案，無需安裝任何第三方核心驅動程式。
- **清晰顯示連線名稱**：透過僅限本機 `lo0` 的 `dnssd` 解析，Finder 側邊欄直接顯示連線**名稱**，取代 `127.0.0.1` 或 `.local` 後綴。
- **智慧串流讀取 — 瀏覽資料夾不預先下載檔案**：目錄清單 (`PROPFIND`) 快取 `15s`，自動提供虛擬防掃描旗標阻斷 QuickLook / Spotlight / FSEvents 背景抓取，並於本機攔截 macOS 中繼垃圾檔案 (`._*`、`.DS_Store`、`.TemporaryItems`)；僅按需進行分片 `Range` 串流讀取，斷線即止。
- **三層自動卸載防護**：手動斷線、Finder 退出 (`⏏`)、結束應用程式 (`⌘Q`) 或異常當機 (`-S` + `atexit`) 皆會立即安全卸載，並於下次啟動時清理殘留掛載。

### ⚡ 3. 快速設定 (`自動連線` & `自動掛載`) 與免重載介面
- **項目右下角快速切換鈕**：
  - **`自動連線`**（支援所有協定）：啟動 macSSH 或開啟設定檔時自動建立連線。
  - **`自動掛載`**（**僅限 FTP**）：啟動時背景靜默掛載至 Finder，且每次手動點擊 **連線 (Connect)** 時自動觸發掛載。
- **免重新載入即時更新**：切換 `自動連線`、`自動掛載`、`Saved` 或 `SOCKS5` 時僅原地更新該項目，不閃爍整頁或重置捲動位置，並支援在 Touch ID 解鎖後自動銜接執行。

### 🌐 4. 原生 OpenSSH SOCKS5 代理與行程生命週期管理
- **Headless `/usr/bin/ssh -D` 通道**：透過 `forkpty` 執行系統 OpenSSH，支援 `127.0.0.1` 本機或 `0.0.0.0` 區域網路共享（自動顯示 LAN IP），睡眠喚醒穩定不斷線。
- **衝突偵測與行程清理**：連接埠衝突自動停用代理並顯示 5 秒 Toast；`NativeProcessRegistry` 透過 `atexit`、訊號處理與啟動巡檢確保無殘留孤兒行程。

### 📂 5. 雙欄瀏覽、多執行緒 FTP 與通用檔案檢視器
- **雙向拖放與多執行緒 FTP (`1–32` 執行緒，預設 `10`)**：可在設定、單一連線或傳輸佇列底部即時調整並行數；支援資料夾遞迴上傳/下載、批次覆蓋確認（取代 / 全部取代 / 略過 / 取消）及 `>= 4 MB` 檔案多段並行下載。
- **五合一通用檔案檢視器**：純文字/程式碼（行號+搜尋+轉開啟編輯器）、圖片縮放、`PDFKit` PDF、原生 `AVKit` 音訊/視訊播放器（`.mp4`/`.mov`/`.mp3`）以及十六進位 Binary 檢視器；搭配 **Edit With** 可於外部編輯器按 `⌘S` 時自動上傳同步。

### 📊 6. 傳輸佇列篩選/重試、即時記錄與原生 macOS 體驗
- **佇列統計與批次重試**：底部狀態膠囊即時顯示成功／失敗數量（支援點擊快篩），提供狀態篩選、檔名篩選以及單一/批次**重試失敗項目**按鈕。
- **即時活動記錄 (`⌘⇧L`)**：保存最新 200 筆記錄，支援層級與分類篩選及 `↕︎` 拖曳調整高度；Release 版具備零配置負擔記錄機制。
- **即時斷網監控 & 自動重連**：`NWPathMonitor` 觸發紅色閃爍警示與 5 秒自動消退通知，恢復連線後按 `0s → 5s → 10s` 自動重連並重新整理 Finder 掛載。
- **完整系統整合**：工具列一鍵切換 **深色 ↔ 淺色 (`Dark`/`Light`)** 外觀、側邊欄／列表空白處右鍵建立選單、完整 macOS 頂部選單列、關閉視窗自動隱藏 Dock 圖示，支援 **Touch ID** 鎖定、**AES-256-GCM** 設定檔加密與 **6 種語言**。

---

## 📸 應用截圖 (Screenshots)

| 連線管理與側邊欄 | 右鍵選單與快捷操作 |
|:---:|:---:|
| ![Connection Manager](../screens/screen-1.png) | ![Context Menu](../screens/screen-2.png) |
| *雙欄極簡佈局，資料夾分類，快速設定一目瞭然* | *右鍵選單：Finder 掛載、SOCKS5 代理、終端機、檔案瀏覽* |

| 雙欄檔案瀏覽器與傳輸佇列 | 內建 SSH 終端機 |
|:---:|:---:|
| ![File Browser](../screens/screen-3.png) | ![SSH Terminal](../screens/screen-4.png) |
| *雙向原生拖曳、路徑直達、即時傳輸速度與 ETA* | *零延遲 xterm-256color 終端機模擬器* |

---

## 💽 安裝與使用指南 (Installation & Setup)

### 系統需求
- **macOS**：15.0+ (Sequoia | Tahoe)。
- **架構**：Universal 2 (完美支援 **Apple Silicon M1/M2/M3/M4** 與 **Intel x86_64** 晶片)。

### 1. 下載 DMG 安裝檔
從 [GitHub Releases](https://github.com/devduong/macSSH/releases) 下載最新發布的 `macSSH_Universal_x.x.x.dmg`。

### 2. 安裝應用程式
開啟 `.dmg` 映像檔並將 **macSSH.app** 拖入 **Applications (應用程式)** 資料夾 (`/Applications`)。

### 3. 首次啟動與 macOS Gatekeeper 安全提示處理

> [!WARNING]
> **安全警告 (Warning)**  
> 由於 macSSH 是免費的開源專案且未購買昂貴的 Apple 開發者付費憑證簽名，macOS Gatekeeper 安全防護可能會提示：*「無法打開 macSSH，因為無法驗證開發者」* 或 *「macOS 無法驗證此 App 是否包含惡意軟體」*。

打開 App 的步驟：
1. 打開 Mac 上的 **系統設定 (System Settings)**。
2. 進入 **隱私權與安全性 (Privacy & Security)**。
3. 向下捲動至 **安全性 (Security)** 區域。
4. 點擊提示「已阻擋使用 macSSH」旁邊的 **「強制打開 (Open Anyway)」** 按鈕。
5. 在彈出的二次確認對話框中點擊 **「打開 (Open)」** 並輸入 Mac 密碼或使用 Touch ID。

*(替代方案：在 Finder 中按右鍵 / 按住 Control 點擊 `macSSH.app` -> 選擇 **打開 (Open)** -> 再次點擊 **打開** 即可)。*

---

### 從原始碼編譯建置

#### 環境需求
- **Xcode**：16.0 或更高版本。
- **macOS SDK**：15.0 或更高版本。
- **Swift**：5.9+。

#### 建置步驟

1. **複製儲存庫**：
   ```bash
   git clone https://github.com/devduong/macSSH.git
   cd macSSH
   ```

2. **在 Xcode 中開啟專案**：
   ```bash
   open macSSH.xcodeproj
   ```

3. **編譯應用程式**：
   ```bash
   xcodebuild -project macSSH.xcodeproj -scheme macSSH -configuration Release build
   ```
   *或在 Xcode 中選擇 `macSSH` Scheme 並按 `Cmd + B`。*

4. **啟動建置出的應用程式**：
   ```bash
   open $(xcodebuild -project macSSH.xcodeproj -scheme macSSH -configuration Release -showBuildSettings | grep -m 1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')/macSSH.app
   ```
   *或在 Xcode 中按 `Cmd + R` 直接執行。*

---

## ☕ 贊助與支持 (Donate)

**macSSH** 是一款開源且免費的專案，致力於為 macOS 社群帶來高效愉悅的伺服器管理體驗。如果 macSSH 對您的工作有所幫助，歡迎贊助一杯咖啡支持後續的開發與維護！❤️

### 1. 透過 Ko-fi 與 GitHub 支持
- ☕ **Ko-fi 贊助**：[https://ko-fi.com/X4P324ZPZ3](https://ko-fi.com/X4P324ZPZ3)
- ⭐ **在 GitHub 點亮 Star**：[devduong/macSSH](https://github.com/devduong/macSSH)

### 2. 加密貨幣贊助 (Crypto Donation)
您可以透過 **BNB Smart Chain (BEP20)** 發送任何代幣（如 *USDT、BNB、BUSD、USDC 等*）至下方錢包地址：

- **網路 (Network)**：`BEP20 (BSC – Binance Smart Chain)`
- **錢包地址 (Wallet Address)**：
  ```text
  0xe26c0DC422EF744816Ca3B2d210e6214fdC4e18E
  ```

---

## 🙏 致謝與來源 (Acknowledgments)

- 🌟 **特別鳴謝 [macnev2013](https://github.com/macnev2013)** — `macSCP` 與 `anySCP` 的作者。非常感謝他早期出色的設計理念與專案基礎，為 **macSSH** 的構想與演進提供了至關重要的靈感。
- 🚀 [Citadel](https://github.com/Orlandos-nl/Citadel) (Joannis Orlandos) & [SwiftNIO](https://github.com/apple/swift-nio) / [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh) (Apple) — 核心 SSH、SFTP 與 WebDAV HTTP 網路層基礎。
- 💻 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (Miguel de Icaza) — 強大的 macOS 終端機模擬函式庫。
- 🎨 [SF Symbols](https://developer.apple.com/sf-symbols/) (Apple) — 原生 macOS 系統圖示體系。

---

## 📄 授權協議 (License)

本專案基於 **MIT License** 協定開源 — 詳見 [LICENSE](../LICENSE) 檔案。

---

<p align="center">
  專為 macOS 使用者精心打造 ❤️
</p>
