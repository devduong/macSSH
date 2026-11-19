<p align="center">
  <img src="../screens/logo.png" alt="macSSH Logo" width="160"/>
</p>

<h1 align="center">macSSH</h1>

<p align="center">
  <strong>专为 macOS 打造的原生 SSH / FTP / SMB 服务器管理、Finder 读写挂载、终端模拟器与动态 SOCKS5 代理工具</strong>
</p>

<p align="center">
  <em>纯 Swift & SwiftUI 开发 • 通用二进制架构 (Apple 芯片 & Intel)</em>
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
  <strong>简体中文</strong> •
  <a href="README_ZH_TW.md">繁體中文</a> •
  <a href="README_RU.md">Русский</a> •
  <a href="README_FR.md">Français</a>
</p>

---

## ⚠️ 重要说明：仅支持 macOS (macOS Only)

> [!IMPORTANT]
> **macSSH 是专门为 Apple macOS 平台量身打造的原生应用。**
> 100% 采用 **SwiftUI**、**AppKit**、**SwiftData**、**Network.framework**、**AVKit**、**PDFKit**、**NetFS** 以及 Apple 原生 **LocalAuthentication (Touch ID)** 框架开发。
>
> 本应用**不支持** Windows 或 Linux 系统，具有极致的原生响应速度、零输入延迟和极低的系统内存占用。

---

## 🌟 项目概述

**macSSH** 为在 Mac 上管理远程服务器的开发者、DevOps 与运维工程师提供了一站式原生解决方案：

- **多协议支持 (`SSH`、`FTP`、`SMB`)**：统一管理 **SSH/SFTP**、**FTP/FTPS** 与 **SMB/CIFS** 服务器，自动匹配默认端口与协议图标/颜色，支持匿名/访客登录及自动 SMB 共享发现。
- **Finder 原生读写挂载（FTP & SFTP）**：通过内置 **SwiftNIO WebDAV Class 2** 环回桥接与 `/sbin/mount_webdav -S`，直接在 **macOS Finder** 中以读写模式挂载远程目录 — **无需 macFUSE、FUSE-T 或 `sudo`**。
- **双栏文件管理器 & 多线程 FTP 传输**：本地 ⇄ 远程 ⇄ Finder 双向原生拖拽、递归文件夹传输，以及可自定义的 **多线程 FTP 传输（默认 10 线程，支持 1–32）** 与大文件分段并行下载。
- **内置通用文件预览器**：支持直接在应用内预览 SSH、FTP 和 SMB 服务器的文本/代码、图片、PDF、音视频 (`AVKit`) 及二进制 Hex/ASCII 内容。
- **快捷开关 (`自动连接` 与 FTP `自动挂载`)**：连接条目右下角提供零刷新即时开关，支持启动 / 加载配置时自动执行，以及点击 Connect 连接 FTP 时自动挂载。
- **原生 OpenSSH 终端与 SOCKS5 代理**：60 FPS `xterm-256color` 终端、一键启动 macOS `Terminal.app`、稳定的 `/usr/bin/ssh -D` 代理隧道及 `NativeProcessRegistry` 防孤儿进程管理。
- **实时网络监控、自动重连与菜单栏后台**：`NWPathMonitor` 断网检测与递进重连、关闭全部窗口时自动隐藏 Dock 图标常驻菜单栏。

---

## ✨ 核心功能与特性

### 🔌 1. 多协议服务器管理 (`SSH` / `FTP` / `SMB`)
- **协议切换器 (`SSH | FTP | SMB`)**：新建或编辑连接时自动匹配默认端口（`22` / `21` / `445`）及专属协议图标与配色。
- **FTP / FTPS 引擎**：基于系统 `/usr/bin/curl`，凭据通过 stdin 安全传递（不暴露于命令行参数），兼容 Unix 及 Windows/IIS 列表解析，支持匿名登录。
- **SMB / CIFS 引擎**：集成 Apple `NetFS.framework` 与 `/usr/bin/smbutil`，支持直连 `host/ShareName` 或自动扫描服务器根共享目录，断开时自动清理卸载。

### 💽 2. 免驱动读写挂载到 Finder (Loopback WebDAV)
- **原生读写体验**：内置 **SwiftNIO WebDAV Class 2** 服务与 `/sbin/mount_webdav -S -o browse`，支持直接在 Finder 中浏览、拷贝、编辑和删除远程 FTP/SFTP 文件，无需安装任何第三方内核驱动。
- **清晰显示连接名称**：通过仅限本机 `lo0` 的 `dnssd` 解析，Finder 边栏直接显示连接**名称**，告别 `127.0.0.1` 或 `.local` 后缀。
- **智能流式读取 — 浏览目录不预先下载文件**：目录列表 (`PROPFIND`) 缓存 `15s`，自动注入虚拟防扫描标识阻断 QuickLook / Spotlight / FSEvents 后台爬取，并拦截 macOS 元数据垃圾文件 (`._*`、`.DS_Store`、`.TemporaryItems`)；仅按需进行分片 `Range` 流式读取，断开即止。
- **三层自动卸载保障**：主动断开、Finder 推出 (`⏏`)、退出应用 (`⌘Q`) 或异常崩溃 (`-S` + `atexit`) 均能瞬间安全卸载，并在下次启动时清理残留。

### ⚡ 3. 快捷设置 (`自动连接` & `自动挂载`) 与无刷新更新
- **条目右下角快捷按钮**：
  - **`自动连接`**（支持所有协议）：打开 macSSH 或加载配置文件时自动建立会话。
  - **`自动挂载`**（**仅支持 FTP**）：启动时静默挂载到 Finder，且每次点击 **连接 (Connect)** 时自动触发挂载。
- **零重载即时响应**：点击切换 `自动连接`、`自动挂载`、`Saved` 或 `SOCKS5` 时仅原地刷新当前条目，绝不刷新整页或重置滚动位置，并兼容 Touch ID 解锁后延迟执行。

### 🌐 4. 原生 OpenSSH SOCKS5 代理与进程管理
- **Headless `/usr/bin/ssh -D` 隧道**：通过 `forkpty` 运行系统 OpenSSH，支持 `127.0.0.1` 本机或 `0.0.0.0` 局域网共享（自动显示 LAN IP），稳健应对睡眠唤醒。
- **冲突检测与生命周期保护**：端口冲突自动降级并弹窗提示 5 秒；`NativeProcessRegistry` 通过 `atexit`、信号处理器及启动巡检确保绝无僵尸子进程残留。

### 📂 5. 双栏浏览、多线程 FTP 与通用文件查看器
- **双向拖拽与多线程 FTP (`1–32` 线程，默认 `10`)**：在设置、单条连接或传输队列底部一键调节并发数；支持文件夹递归上传/下载、集中覆盖确认（替换/全部替换/跳过/取消）与 `>= 4 MB` 文件多段并发下载。
- **五合一通用文件查看器**：文本/代码（行号+搜索+跳转编辑）、图片缩放、`PDFKit` PDF、原生 `AVKit` 音视频播放器（`.mp4`/`.mov`/`.mp3`）以及十六进制 Binary 检查器；配合 **Edit With** 可在外部编辑器 `⌘S` 时自动回传。

### 📊 6. 传输队列筛选/重试、实时日志与原生 macOS 体验
- **队列统计与一键重试**：底部统计胶囊实时显示成功/失败数量（点击快速过滤），支持状态筛选、文件名过滤以及单条/批量**重试失败项**。
- **实时活动日志 (`⌘⇧L`)**：保留最新 200 条日志，支持级别/分类过滤及 `↕︎` 拖拽调高；Release 构建零开销。
- **实时断网检测 & 自动重连**：`NWPathMonitor` 触发红色闪烁预警与 5 秒自动消隐通知，网络恢复后按 `0s → 5s → 10s` 自动重连并刷新 Finder 挂载。
- **完整系统融合**：工具栏一键切换 **深色 ↔ 浅色 (`Dark`/`Light`)** 主题、侧边栏/连接列表空白处右键新建菜单、完整 macOS 顶部菜单栏、关闭窗口自动隐藏 Dock 图标，支持 **Touch ID** 锁定、**AES-256-GCM** 配置加密与 **6 种语言**。

---

## 📸 应用截图 (Screenshots)

| 连接管理与侧边栏 | 右键菜单与快捷操作 |
|:---:|:---:|
| ![Connection Manager](../screens/screen-1.png) | ![Context Menu](../screens/screen-2.png) |
| *双栏极简布局，文件夹分类，快捷开关一目了然* | *右键菜单：Finder 挂载、SOCKS5 代理、终端、文件浏览* |

| 双栏文件浏览器与传输队列 | 内置 SSH 终端 |
|:---:|:---:|
| ![File Browser](../screens/screen-3.png) | ![SSH Terminal](../screens/screen-4.png) |
| *双向原生拖拽、路径直达、实时速度与 ETA* | *零延迟 xterm-256color 终端模拟器* |

---

## 💽 安装与使用指南 (Installation & Setup)

### 系统要求
- **macOS**：15.0+ (Sequoia | Tahoe)。
- **架构**：Universal 2 (完美支持 **Apple Silicon M1/M2/M3/M4** 与 **Intel x86_64** 芯片)。

### 1. 下载 DMG 安装包
从 [GitHub Releases](https://github.com/devduong/macSSH/releases) 下载最新发布的 `macSSH_Universal_x.x.x.dmg`。

### 2. 安装应用程序
打开 `.dmg` 镜像并将 **macSSH.app** 拖入 **Applications (应用程序)** 文件夹 (`/Applications`)。

### 3. 首次启动与 macOS Gatekeeper 安全提示处理

> [!WARNING]
> **安全警告 (Warning)**  
> 由于 macSSH 是免费的开源项目且未购买昂贵的 Apple 开发者付费证书签名，macOS Gatekeeper 安全防护可能会提示：*“无法打开 macSSH，因为无法验证开发者”* 或 *“macOS 无法验证此 App 是否包含恶意软件”*。

打开 App 的步骤：
1. 打开 Mac 上的 **系统设置 (System Settings)**。
2. 进入 **隐私与安全性 (Privacy & Security)**。
3. 向下滚动至 **安全性 (Security)** 区域。
4. 点击提示“已阻止使用 macSSH”旁边的 **“仍要打开 (Open Anyway)”** 按钮。
5. 在弹出的二次确认对话框中点击 **“打开 (Open)”** 并输入 Mac 密码或使用 Touch ID。

*(替代方案：在访达 Finder 中右键 / 按住 Control 单击 `macSSH.app` -> 选择 **打开 (Open)** -> 再次点击 **打开** 即可)。*

---

### 从源码编译构建

#### 环境要求
- **Xcode**：16.0 或更高版本。
- **macOS SDK**：15.0 或更高版本。
- **Swift**：5.9+。

#### 构建步骤

1. **克隆仓库**：
   ```bash
   git clone https://github.com/devduong/macSSH.git
   cd macSSH
   ```

2. **在 Xcode 中打开工程**：
   ```bash
   open macSSH.xcodeproj
   ```

3. **编译应用程序**：
   ```bash
   xcodebuild -project macSSH.xcodeproj -scheme macSSH -configuration Release build
   ```
   *或在 Xcode 中选择 `macSSH` Scheme 并按 `Cmd + B`。*

4. **启动构建出的应用**：
   ```bash
   open $(xcodebuild -project macSSH.xcodeproj -scheme macSSH -configuration Release -showBuildSettings | grep -m 1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')/macSSH.app
   ```
   *或在 Xcode 中按 `Cmd + R` 直接运行。*

---

## ☕ 赞助与支持 (Donate)

**macSSH** 是一款开源且免费的项目，致力于为 macOS 社区带来高效愉悦的服务器管理体验。如果 macSSH 对您的工作有所帮助，欢迎赞助一杯咖啡支持后续的开发与维护！❤️

### 1. 通过 Ko-fi 与 GitHub 支持
- ☕ **Ko-fi 赞助**：[https://ko-fi.com/X4P324ZPZ3](https://ko-fi.com/X4P324ZPZ3)
- ⭐ **在 GitHub 点亮 Star**：[devduong/macSSH](https://github.com/devduong/macSSH)

### 2. 加密货币赞助 (Crypto Donation)
您可以通过 **BNB Smart Chain (BEP20)** 发送任何代币（如 *USDT、BNB、BUSD、USDC 等*）至下方钱包地址：

- **网络 (Network)**：`BEP20 (BSC – Binance Smart Chain)`
- **钱包地址 (Wallet Address)**：
  ```text
  0xe26c0DC422EF744816Ca3B2d210e6214fdC4e18E
  ```

---

## 🙏 致谢与来源 (Acknowledgments)

- 🌟 **特别鸣谢 [macnev2013](https://github.com/macnev2013)** — `macSCP` 与 `anySCP` 的作者。非常感谢他早期出色的设计理念与项目基础，为 **macSSH** 的构想与演进提供了至关重要的灵感。
- 🚀 [Citadel](https://github.com/Orlandos-nl/Citadel) (Joannis Orlandos) & [SwiftNIO](https://github.com/apple/swift-nio) / [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh) (Apple) — 核心 SSH、SFTP 与 WebDAV HTTP 网络层基础。
- 💻 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (Miguel de Icaza) — 强大的 macOS 终端模拟库。
- 🎨 [SF Symbols](https://developer.apple.com/sf-symbols/) (Apple) — 原生 macOS 系统图标体系。

---

## 📄 开源协议 (License)

本项目基于 **MIT License** 协议开源 — 详见 [LICENSE](../LICENSE) 文件。

---

<p align="center">
  专为 macOS 用户精心打造 ❤️
</p>
