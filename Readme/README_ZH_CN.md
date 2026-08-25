<p align="center">
  <img src="../screens/logo.png" alt="macSSH Logo" width="160"/>
</p>

<h1 align="center">macSSH</h1>

<p align="center">
  <strong>专为 macOS 打造的原生 SSH 连接管理、双栏 SFTP 浏览器、终端模拟器与动态 SOCKS5 代理工具</strong>
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
> 100% 采用 **SwiftUI**、**AppKit**、**SwiftData** 以及 Apple 原生 **LocalAuthentication (Touch ID)** 与安全框架开发。
> 
> 本应用**不支持** Windows 或 Linux 系统，具有极致的原生响应速度、零输入延迟和极低的系统内存占用。

---

## 🌟 项目概述

**macSSH** 为在 Mac 上管理远程服务器的开发者、DevOps 与运维工程师提供了一站式原生解决方案：

- **双栏 SFTP 文件管理器 (Dual-Pane)**：支持本地与远程文件面板之间的双向拖拽传输，并可直接拖放至 macOS Finder。
- **高性能 SSH 终端**：基于 SwiftTerm 实现的 60 帧 `xterm-256color` 终端模拟器，采用 OpenSSH 标准 PTY 直传模式（输入零延迟），并支持一键直接在 macOS 原生 `Terminal.app` 中启动。
- **动态 SOCKS5 代理 (SSH Tunnel)**：自动通过 SSH 隧道开启内置 SOCKS5 代理服务，支持本机环回 (`127.0.0.1`) 或局域网全网段共享 (`0.0.0.0`)，支持一键切换及端口冲突自动处理。
- **“打开方式”与保存自动同步 (Open With & Auto-Sync)**：可在 Mac 上的任意文本编辑器（VS Code、Xcode、TextEdit 等）中打开远程文件，按下保存 (`⌘S`) 时自动上传覆盖至远程服务器。
- **菜单栏常驻与后台运行**：常驻 macOS 顶部菜单栏，关闭全部窗口后仍可保持 SSH 会话与代理连接。
- **独立安全的配置管理**：支持 JSON 配置文件导入导出、自动记忆并加载上次使用的配置文件、Touch ID 生物识别应用锁以及 AES-256-GCM 密码硬件加密。

---

## ✨ 核心功能与特性

### 🌐 1. 动态 SOCKS5 代理 (SSH Tunnel)
- **一键代理隧道**：连接 SSH 时自动开启 SOCKS5 代理服务，安全转发网络流量。
- **本机与局域网共享**：可选择监听 `127.0.0.1`（仅本机）或 `0.0.0.0`（共享至局域网内其他设备，自动显示当前 Mac 的局域网 IP）。
- **快速切换徽章**：服务器列表行显示紫色 SOCKS5 徽章，点击即可快速开启或关闭代理。
- **智能端口冲突处理**：当端口被占用时，macSSH 会自动安全关闭代理并通过 5 秒毛玻璃 Toast 提示，不影响主 SSH 连接。

### 📂 2. 双栏 SFTP 文件浏览与双向原生拖拽
- **双栏直观布局**：左侧本地文件面板，右侧远程服务器文件面板。
- **双向拖拽支持**：
  - 本地拖向远程直接上传。
  - 远程拖向本地（或特定子目录）立即下载。
  - 支持通过 `NSFilePromiseProvider` 将远程文件直接拖拽至 **macOS Finder**。
- **递归下载整个目录**：自动递归创建多层子目录并完整下载。
- **直接路径输入栏**：支持随时键入或粘贴绝对路径（如 `/var/www`），快捷键 `⌘L` 或 `⇧⌘G`。
- **安全覆盖确认**：当目标路径存在同名文件时，弹出 `NSAlert` 提示选择“覆盖 (Replace)”或“取消 (Cancel)”。
- **精简表格体验**：消除横向滚动条，列宽自适应，支持多选批量删除。

### 📝 3. “打开方式”外部编辑器与保存自动同步
- **任意 Mac 应用打开**：右键菜单提供 `Open With Default App` 与 `Open With…`（智能匹配系统中已安装的 VS Code、Xcode、Sublime Text、TextEdit 等）。
- **`⌘S` 自动同步**：内置 2 秒轮询监听。在外部应用中保存时，自动检测修改并实时上传覆盖至服务器。

### 💻 4. 完整 SSH 终端与零延迟输入
- **流畅终端模拟**：基于 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)，支持 60 FPS 渲染与完整 `xterm-256color`。
- **零延迟直传模式**：遵循 OpenSSH 标准 PTY 模式，主线程字节流直推，彻底消除按键延迟与缓冲卡顿。
- **一键调用 macOS 原生终端**：工具栏与右键菜单提供 **“Open in macOS Terminal”**，通过 AppleScript 一键启动系统自带终端。
- **认证失败重新提示**：自动识别密码错误并弹出密码重试弹窗。

### 📊 5. 传输队列管理面板与实时日志
- **底部 3 标签页控制面板**：
  - 📤 **上传队列 (Upload Queue)**：显示进度百分比、已传输大小、**实时传输速率 (MB/s, KB/s)**、**剩余预估时间 (ETA)** 及取消控制。
  - 📥 **下载队列 (Download Queue)**：实时监控文件下载进度与速率。
  - 📜 **控制台日志 (Log Console)**：带有时间戳 `[HH:mm:ss]` 和颜色分级（`[INFO]`、`[SUCCESS]`、`[WARN]`、`[ERROR]`）的实时 SFTP 操作日志。
- **纯内存运行机制**：传输队列与日志仅在活动会话的内存中保留，关闭窗口后自动释放。

### 🗂️ 6. 现代双栏布局与便捷操作
- **双栏结构**：侧边栏（文件夹、设置、赞助、关于）与连接列表。
- **跨栏拖拽归类**：直接将服务器拖入侧边栏文件夹进行分类管理。
- **双击自动连接**：双击服务器条目立即建立连接并开启文件浏览器。
- **实时在线状态同步**：连接成功后状态指示灯立即变为绿色。
- **快捷操作按钮**：每行均常驻显示 📁 打开文件浏览器 与 `>_` 打开终端 按钮。

### 💾 7. 独立配置管理与生物识别安全
- **JSON 配置文件**：保存 (`⌘S`)、另存为 (`⇧⌘S`)、打开 (`⌘O`)、新建配置 (`⌘⌥N`)。
- **自动记忆配置文件**：记录当前使用的配置文件并在启动时自动重新加载。
- **退出保存提醒**：在存在未保存更改时弹出“保存 / 不保存 / 取消”提示。
- **AES-256-GCM 密码加密**：密码可安全加密并保存于配置文件内，不强制依赖系统 Keychain。
- **Touch ID 指纹锁**：支持使用 Touch ID 或 Mac 开机密码锁定/解锁应用。

### 🌐 8. 多语言国际化架构 (L10N)
- 支持多种语言并具备英文自动降级（Fallback）机制：
  - 🇬🇧 英语 (**English** - 默认降级)
  - 🇻🇳 越南语 (**Tiếng Việt**)
  - 🇨🇳 简体中文 (**简体中文**)
  - 🇹🇼 繁体中文 (**繁體中文**)
  - 🇷🇺 俄语 (**Русский**)
  - 🇫🇷 法语 (**Français**)
- 设置中即时切换语言，无需重启应用。

---

## 📸 应用截图 (Screenshots)

| 连接管理与侧边栏 | 右键菜单与快捷操作 |
|:---:|:---:|
| ![Connection Manager](../screens/screen-1.png) | ![Context Menu](../screens/screen-2.png) |
| *双栏极简布局，文件夹分类管理，快速连接* | *右键菜单：SOCKS5 代理、终端、SFTP 浏览器* |

| 双栏 SFTP 浏览器与传输队列 | 内置 SSH 终端 |
|:---:|:---:|
| ![File Browser](../screens/screen-3.png) | ![SSH Terminal](../screens/screen-4.png) |
| *双向原生拖拽、路径直接跳转、实时传输速度与 ETA* | *零延迟 xterm-256color 终端模拟器* |

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

3. **使用脚本构建并打包 DMG**：
   ```bash
   ./create-dmg.sh
   ```
   *脚本将自动完成 Release Universal 双架构编译、自签名并打包生成最终的 DMG 安装文件，输出至 `build/macSSH.app`。*

4. **启动构建出的应用**：
   ```bash
   open build/macSSH.app
   ```

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
- 🚀 [Citadel](https://github.com/Orlandos-nl/Citadel) (Joannis Orlandos) & [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh) (Apple) — 核心 SSH 与 SFTP 协议基础。
- 💻 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (Miguel de Icaza) — 强大的 macOS 终端模拟库。
- 🎨 [SF Symbols](https://developer.apple.com/sf-symbols/) (Apple) — 原生 macOS 系统图标体系。

---

## 📄 开源协议 (License)

本项目基于 **MIT License** 协议开源 — 详见 [LICENSE](../LICENSE) 文件。

---

<p align="center">
  专为 macOS 用户精心打造 ❤️
</p>
