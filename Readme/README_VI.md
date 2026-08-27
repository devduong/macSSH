# 🚀 macSSH (macOS Native SSH, SFTP & Dynamic SOCKS5 Client)

<p align="center">
  <img src="../screens/icon.png" width="128" height="128" alt="macSSH App Icon" style="border-radius: 22%; box-shadow: 0 8px 24px rgba(0,0,0,0.25);" />
</p>

<p align="center">
  <strong>Ứng dụng Native macOS đỉnh cao cho SFTP Dual-Pane, Dynamic SOCKS5 Proxy & SSH Terminal</strong><br>
  <em>Tương thích hoàn hảo macOS 15.0+ Sequoia | Tahoe (Universal 2: Apple Silicon & Intel)</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2015.0%2B-blue.svg?style=flat-square&logo=apple" alt="macOS Platform" />
  <img src="https://img.shields.io/badge/Architecture-Universal%202%20(arm64%20|%20x86__64)-purple.svg?style=flat-square" alt="Universal 2 Architecture" />
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138.svg?style=flat-square&logo=swift" alt="Swift Version" />
  <img src="https://img.shields.io/badge/License-MIT-green.svg?style=flat-square" alt="MIT License" />
  <a href="https://github.com/devduong/macSSH/releases"><img src="https://img.shields.io/github/downloads/devduong/macSSH/total.svg?style=flat-square&color=orange" alt="GitHub Downloads" /></a>
  <a href="https://ko-fi.com/X4P324ZPZ3"><img src="https://img.shields.io/badge/Donate-Ko--fi-ff5e5b.svg?style=flat-square&logo=kofi" alt="Donate Ko-fi" /></a>
</p>

---

## 🌍 Ngôn Ngữ / Languages

[English](../README.md) | [Tiếng Việt](README_VI.md) | [简体中文](README_ZH_CN.md) | [繁體中文](README_ZH_TW.md) | [Русский](README_RU.md) | [Français](README_FR.md)

---

## 🌟 Giới Thiệu Tổng Quan

**macSSH** là ứng dụng native độc quyền dành riêng cho macOS, được phát triển 100% bằng **SwiftUI**, **AppKit** và **SwiftData**. Ứng dụng mang đến trải nghiệm đồ hoạ mượt mà, tốc độ phản hồi tức thì và hiệu năng tối ưu:

- 🌐 **Dynamic SOCKS5 SSH Tunnel**: Tự động mở SOCKS5 Proxy server (Localhost hoặc chia sẻ mạng LAN) qua kết nối SSH.
- 📂 **SFTP Browser Dạng 2 Khung (Dual-Pane)**: Kéo thả hai chiều (Local ⇄ Remote), kéo thả trực tiếp ra Finder, tải thư mục đệ quy và thanh gõ đường dẫn trực tiếp.
- 📝 **Chỉnh Sửa Bằng Ứng Dụng Ngoài ("Open With")**: Mở tệp từ xa bằng VS Code, Xcode, TextEdit,... và tự động upload ghi đè lên server ngay khi bấm Save (`⌘S`).
- 💻 **SSH Terminal Zero-Latency**: Giả lập `xterm-256color` siêu mượt 60 FPS, phản hồi gõ phím tức thì và hỗ trợ mở trực tiếp sang Terminal.app của macOS.
- 📜 **Khung Nhật Ký Hoạt Động (Activity Logs)**: Bảng console trực tiếp theo dõi toàn bộ sự kiện SSH, SOCKS5, SFTP, Auth và Database.
- 💾 **Lưu Cấu Hình Độc Lập**: Lưu/Nạp cấu hình JSON, mã hoá mật khẩu AES-256-GCM không phụ thuộc Keychain, bảo mật sinh trắc học Touch ID.

---

## ✨ Tính Năng Nổi Bật

### 🌐 1. Dynamic SOCKS5 Proxy (SSH Tunnel)
- **Tự Động Mở SOCKS5 Proxy**: Mở proxy server cục bộ an toàn định tuyến toàn bộ lưu lượng qua phiên SSH đang kết nối.
- **Chia Sẻ Mạng LAN**: Hỗ trợ binding `127.0.0.1` (riêng máy Mac) hoặc `0.0.0.0` (chia sẻ cho mọi thiết bị trong mạng Wi-Fi/LAN, tự động phát hiện IP LAN).
- **Badge Bật/Tắt Nhanh**: Nút badge SOCKS5 màu tím trên từng server cho phép bật/tắt proxy nhanh mà không cần mở form chỉnh sửa.
- **Tự Động Xử Lý Trùng Port**: Tự động phát hiện cổng bị chiếm dụng (`Address already in use`), ngắt proxy an toàn và hiện thông báo Toast 5 giây mà không làm gián đoạn kết nối SSH.

### 📂 2. Quản Lý Tệp SFTP Dual-Pane & Kéo Thả 2 Chiều
- **Bố Cục 2 Khung Song Song (Dual-Pane)**: Khung bên trái duyệt tệp Local (máy Mac), khung bên phải duyệt tệp Remote (Server).
- **Kéo Thả Hai Chiều Native**:
  - Kéo file/folder từ Local thả sang Remote để tải lên.
  - Kéo file/folder từ Remote thả sang Local (hoặc thả vào thư mục con) để tải xuống ngay lập tức.
  - Kéo thả trực tiếp từ Remote ra **Finder** của macOS thông qua `NSFilePromiseProvider`.
- **Tải Xuống Thư Mục Đệ Quy (Recursive Download)**: Tự động tạo và tải toàn bộ cấu trúc thư mục lồng nhau.
- **Thanh Nhập Đường Dẫn Trực Tiếp (Direct Path TextField)**: Dễ dàng gõ hoặc dán đường dẫn (`/var/www`, `~/.config`), hỗ trợ phím tắt `⌘L` hoặc `⇧⌘G`.
- **Cảnh Báo Ghi Đè An Toàn**: Modal `NSAlert` xác nhận Ghi đè (Replace) hoặc Hủy (Cancel) khi tệp đích đã tồn tại.
- **Bảng Tệp Tối Ưu**: Không còn thanh cuộn ngang vướng víu; hỗ trợ chọn nhiều tệp và xóa hàng loạt (Multi-file batch delete).

### 📝 3. Tính Năng "Open With" & Tự Động Đồng Bộ Khi Lưu
- **Mở Tệp Remote Bằng Ứng Dụng macOS**: Menu chuột phải cung cấp tùy chọn `Open With Default App` và `Open With…` (tự động gợi ý ứng dụng phù hợp như VS Code, Xcode, Sublime Text, TextEdit, Preview,...).
- **Auto-Sync Khi Bấm `⌘S`**: Giám sát file bằng Polling Timer (chu kỳ 2s). Khi người dùng nhấn Save (`⌘S`) trong editor ngoài, macSSH tự động upload tệp đã sửa và ghi đè trực tiếp lên server remote kèm log console.

### 💻 4. SSH Terminal Toàn Diện & Zero-Latency
- **Terminal Nội Bộ Siêu Mượt**: Tích hợp engine [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) hỗ trợ đầy đủ chuẩn `xterm-256color`, 60 FPS mượt mà.
- **Zero-Latency Direct Feed**: Cấu hình PTY OpenSSH chuẩn, đưa trực tiếp luồng byte vào terminal trên Main Thread giúp ký tự gõ phản hồi tức thì.
- **Khởi Chạy macOS Terminal Gốc**: Nút **"Open in macOS Terminal"** trên toolbar và context menu mở phiên SSH sang ứng dụng **Terminal.app** của macOS chỉ với 1 click qua AppleScript.
- **Tự Động Nhập Lại Mật Khẩu**: Khi phát hiện lỗi sai mật khẩu hoặc xác thực SSH thất bại, ứng dụng tự động hiển thị sheet nhập lại mật khẩu trực quan.

### 📊 5. Bảng Quản Lý Truyền Tải & Log Console SFTP
- **Bảng Điều Khiển 3 Tab Dưới Đáy File Browser**:
  - 📤 **Upload Queue**: Danh sách file đang tải lên, tiến trình %, dung lượng, **tốc độ realtime (MB/s, KB/s)**, **thời gian còn lại (ETA)**, nút Hủy.
  - 📥 **Download Queue**: Theo dõi tiến trình tải xuống, tốc độ và ETA thời gian thực.
  - 📜 **Log Console**: Luồng nhật ký chi tiết các lệnh SFTP với timestamp `[HH:mm:ss]`, phân cấp màu sắc (`[INFO]`, `[SUCCESS]`, `[WARN]`, `[ERROR]`).
- **In-Memory Sạch Sẽ**: Dữ liệu queue và log chỉ lưu trong RAM theo phiên làm việc, tự động giải phóng khi đóng cửa sổ.

### 🗂️ 6. Giao Diện 2 Cột Tinh Gọn & Thao Tác Nhanh
- **2-Column NavigationSplitView**: Bố cục Sidebar (Thư mục, Cài đặt, Ủng hộ) và Danh sách kết nối hiện đại.
- **Kéo Thả Phân Loại Server**: Kéo thả Server từ danh sách vào các Thư mục ở Sidebar (Cross-column Drag & Drop).
- **Double-Click Kết Nối Nhanh**: Nhấp đúp vào bất kỳ server nào để tự động kết nối và mở ngay File Browser.
- **Đồng Bộ Trạng Thái Tức Thì**: Chấm trạng thái màu xanh lá cập nhật realtime ngay khi kết nối thành công.
- **Nút Thao Tác Nhanh**: Tích hợp sẵn 2 nút mở File Browser 📁 và mở Terminal `>_` ngay trên từng hàng server.

### 💾 7. Quản Lý Cấu Hình & Bảo Mật Độc Lập
- **Xuất / Nạp Cấu Hình JSON**: Dễ dàng lưu (`⌘S`), lưu thành file mới (`⇧⌘S`), mở file (`⌘O`), hoặc tạo cấu hình mới (`⌘⌥N`).
- **Tự Động Nhớ File Cấu Hình**: Ghi nhớ file config đang làm việc và tự động nạp lại khi khởi động ứng dụng.
- **Cảnh Báo Lưu Khi Thoát**: Hộp thoại cảnh báo 3 lựa chọn (Lưu / Không lưu / Hủy) nếu có thay đổi chưa được ghi vào file.
- **Mã Hóa Mật Khẩu AES-256-GCM**: Mật khẩu được mã hóa và lưu an toàn vào file cấu hình (nếu bật), không phụ thuộc vào Keychain hệ thống.
- **Bảo Mật Sinh Trắc Học**: Hỗ trợ khóa ứng dụng bằng Touch ID hoặc mật khẩu máy Mac qua Apple LocalAuthentication.

### 📜 8. Khung Nhật Ký Hoạt Động Trực Tiếp (Activity Log Console)
- **Ghi Nhận Nhật Ký Toàn Hệ Thống**: Stream realtime hoạt động hệ thống, kết nối SSH, vòng đời SOCKS5 proxy, truyền tệp SFTP và xác thực.
- **Khung Điều Khiển Thu Gọn & Co Giãn**: Nút Checkbox tiện lợi (`⌘⇧L`) trên thanh công cụ với khả năng kéo thả chỉnh độ cao linh hoạt (`↕︎` native resize cursor).
- **Bộ Lọc Nâng Cao & Tìm Kiếm**: Lọc nhật ký theo cấp độ (`INFO`, `SUCCESS`, `WARN`, `ERROR`), theo danh mục (`Network`, `SOCKS5`, `SFTP`, `Terminal`, `Auth`, `Database`, `App`), hoặc ô tìm kiếm realtime.
- **Xuất & Kiểm Thử Nhanh**: Sao chép nhật ký vào Clipboard với 1 click, xóa sạch lịch sử hoặc phát log thử nghiệm.

### 🌐 9. Hỗ Trợ Đa Ngôn Ngữ (Localization L10N)
- Hệ thống đa ngôn ngữ theo chuẩn key-based với cơ chế tự động Fallback Tiếng Anh:
  - 🇬🇧 Tiếng Anh (**English** - Default Fallback)
  - 🇻🇳 **Tiếng Việt**
  - 🇨🇳 Tiếng Trung Giản thể (**简体中文**)
  - 🇹🇼 Tiếng Trung Phồn thể (**繁體中文**)
  - 🇷🇺 Tiếng Nga (**Русский**)
  - 🇫🇷 Tiếng Pháp (**Français**)
- Đổi ngôn ngữ trực tiếp trong Settings và có hiệu lực ngay lập tức.

---

## 📸 Hình Ảnh Ứng Dụng (Screenshots)

| Quản Lý Kết Nối & Thư Mục | Menu Chuột Phải & Thao Tác Nhanh |
|:---:|:---:|
| ![Connection Manager](../screens/screen-1.png) | ![Context Menu](../screens/screen-2.png) |
| *Giao diện 2 cột tinh gọn, phân nhóm thư mục, kết nối nhanh* | *Menu chuột phải: SOCKS5 proxy, Terminal, SFTP* |

| Trình Duyệt Tệp Song Song & Hàng Đợi | Giả Lập SSH Terminal Tích Hợp |
|:---:|:---:|
| ![File Browser](../screens/screen-3.png) | ![SSH Terminal](../screens/screen-4.png) |
| *Kéo thả hai chiều, thanh nhập đường dẫn, tốc độ truyền tải & ETA realtime* | *Terminal xterm-256color không độ trễ, giao diện native mượt mà* |

---

## 💽 Hướng Dẫn Cài Đặt & Thiết Lập (Installation & Setup)

### Yêu Cầu Hệ Thống
- **macOS**: 15.0+ (Sequoia | Tahoe).
- **Kiến Trúc**: Universal 2 (Hỗ trợ tối ưu cả **Apple Silicon M1/M2/M3/M4** và **Intel x86_64**).

### Lựa Chọn 1: Tải Bản Cài Đặt DMG (Khuyên dùng)
1. Tải phiên bản mới nhất `macSSH_Universal_x.x.x.dmg` từ mục [GitHub Releases](https://github.com/devduong/macSSH/releases).
2. Mở tệp `.dmg` đã tải về và kéo biểu tượng **macSSH.app** vào thư mục **Applications** (`/Applications`).

> [!IMPORTANT]
> **Mở Ứng Dụng Lần Đầu (Vượt macOS Gatekeeper):**
> Nếu macOS hiển thị thông báo *"macSSH cannot be opened because Apple cannot check it for malicious software"*:
> 1. Mở **System Settings** (Cài đặt hệ thống) trên máy Mac của bạn.
> 2. Chọn mục **Privacy & Security** (Quyền riêng tư & Bảo mật).
> 3. Cuộn xuống phần **Security** (Bảo mật).
> 4. Nhấn vào nút **"Open Anyway"** (Mở dù sao đi nữa) bên cạnh thông báo macSSH bị chặn.
> 5. Trong hộp thoại xác nhận, nhấn **"Open"** (Mở) và nhập mật khẩu máy Mac hoặc dùng Touch ID.

---

### Lựa Chọn 2: Biên Dịch Từ Mã Nguồn (Build from Source)

#### Yêu Cầu Phát Triển
- **Xcode**: 16.0 trở lên.
- **macOS SDK**: 15.0 trở lên.
- **Swift**: 5.9+.

#### Các Bước Thực Hiện

1. **Clone repository**:
   ```bash
   git clone https://github.com/devduong/macSSH.git
   cd macSSH
   ```

2. **Mở dự án trong Xcode**:
   ```bash
   open macSSH.xcodeproj
   ```

3. **Biên dịch ứng dụng**:
   ```bash
   xcodebuild -project macSSH.xcodeproj -scheme macSSH -configuration Release build
   ```
   *Hoặc chọn scheme `macSSH` trong Xcode và nhấn `Cmd + B`.*

4. **Khởi chạy ứng dụng**:
   ```bash
   open $(xcodebuild -project macSSH.xcodeproj -scheme macSSH -configuration Release -showBuildSettings | grep -m 1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')/macSSH.app
   ```
   *Hoặc nhấn `Cmd + R` để chạy trực tiếp trong Xcode.*

---

## ☕ Ủng Hộ Dự Án (Donate)

**macSSH** là dự án mã nguồn mở phi lợi nhuận được phát triển với mục tiêu mang lại công cụ làm việc tốt nhất cho cộng đồng macOS. Nếu bạn thấy macSSH hữu ích cho công việc hàng ngày, hãy ủng hộ tác giả một tách cà phê để tiếp tục duy trì và phát triển dự án nhé! ❤️

### 1. Hỗ Trợ Qua Ko-fi & GitHub
- ☕ **Ko-fi**: [https://ko-fi.com/X4P324ZPZ3](https://ko-fi.com/X4P324ZPZ3)
- 🌟 **GitHub Star**: Tặng một ngôi sao tại [https://github.com/devduong/macSSH](https://github.com/devduong/macSSH)

### 2. Ủng Hộ Qua Tiền Mã Hóa (Crypto Donation - BEP20)
- **Network**: `BEP20 (Binance Smart Chain - BSC)`
- **Địa Chỉ Ví**: `0xe26c0DC422EF744816Ca3B2d210e6214fdC4e18E`
- *(Chấp nhận mọi token trên mạng BEP20 như USDT, BNB, BUSD, ETH...)*

---

## 📜 Giấy Phép & Bản Quyền (License)

Dự án được phân phối dưới giấy phép **MIT License** — xem tệp [LICENSE](../LICENSE) để biết thêm chi tiết.

Cảm ơn đặc biệt tới **macnev2013** (tác giả dự án gốc `macSCP`) đã tạo tiền đề cảm hứng cho sự phát triển của macSSH!
