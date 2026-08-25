<p align="center">
  <img src="../screens/logo.png" alt="macSSH Logo" width="160"/>
</p>

<h1 align="center">macSSH</h1>

<p align="center">
  <strong>Trình Quản lý Kết nối SSH, Trình duyệt SFTP Dual-Pane, Terminal Emulator & Dynamic SOCKS5 Proxy Native Dành Riêng Cho macOS</strong>
</p>

<p align="center">
  <em>100% Swift & SwiftUI • Universal Binary (Apple Silicon & Intel)</em>
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
  <strong>Tiếng Việt</strong> •
  <a href="README_ZH_CN.md">简体中文</a> •
  <a href="README_ZH_TW.md">繁體中文</a> •
  <a href="README_RU.md">Русский</a> •
  <a href="README_FR.md">Français</a>
</p>

---

## ⚠️ Lưu ý quan trọng: Chỉ dành cho macOS (macOS Only)

> [!IMPORTANT]
> **macSSH được xây dựng và tối ưu chuyên biệt cho Apple macOS.**
> Ứng dụng là phần mềm native 100% được phát triển bằng **SwiftUI**, **AppKit**, **SwiftData**, kết hợp các framework hệ thống của Apple như **LocalAuthentication (Touch ID)** và **Keychain Services**.
> 
> Ứng dụng **KHÔNG** hỗ trợ Windows hay Linux — mang lại tốc độ phản hồi native cực nhanh, độ trễ bằng 0 và chiếm dụng bộ nhớ RAM tối thiểu.

---

## 🌟 Tổng Quan Dự Án

**macSSH** cung cấp giải pháp toàn diện cho các lập trình viên, DevOps và quản trị viên hệ thống khi làm việc với máy chủ từ xa trên máy Mac:

- **Duyệt & Quản lý Tệp Từ Xa (SFTP Dual-Pane)**: Kéo thả 2 chiều trực quan giữa máy Mac (Local) và máy chủ (Remote), hỗ trợ kéo thả tệp trực tiếp ra Finder của macOS.
- **SSH Terminal Hiệu Năng Cao**: Trình giả lập `xterm-256color` siêu mượt (60 FPS) hỗ trợ chuẩn OpenSSH PTY Zero-latency Direct Feed (gõ phản hồi tức thì), cùng nút mở trực tiếp bằng macOS `Terminal.app` gốc chỉ với 1 click.
- **Dynamic SOCKS5 Proxy qua SSH Tunnel**: Tự động mở SOCKS5 Proxy server nội bộ qua đường hầm SSH, hỗ trợ định tuyến cả Localhost (`127.0.0.1`) lẫn chia sẻ toàn mạng LAN (`0.0.0.0`) kèm cơ chế tự phục hồi khi xung đột cổng.
- **Mở Bằng Ứng Dụng Ngoài & Tự Động Đồng Bộ (Open With & Auto-Sync)**: Mở file remote bằng bất kỳ IDE/Editor nào trên Mac (VS Code, TextEdit, Xcode, Sublime Text,...) và tự động upload ghi đè lên server ngay khi bấm Save (`⌘S`).
- **Thường Trú Menu Bar & Chạy Ngầm**: Duy trì kết nối SSH và SOCKS5 Proxy liên tục ngay cả khi đóng tất cả cửa sổ chính.
- **Quản Lý Cấu Hình Độc Lập & Bảo Mật**: Xuất/nhập file cấu hình JSON, tự động nạp lại file cấu hình gần nhất, khóa ứng dụng Touch ID và mã hóa mật khẩu AES-256-GCM an toàn.

---

## ✨ Tính Năng & Chức Năng Nổi Bật

### 🌐 1. Dynamic SOCKS5 Proxy (SSH Tunnel)
- **Tạo Proxy Tự Động**: Khởi chạy một SOCKS5 Proxy server định tuyến toàn bộ lưu lượng qua kết nối SSH an toàn.
- **Hỗ Trợ Mạng Cục Bộ & LAN**: Cho phép lắng nghe trên `127.0.0.1` (chỉ máy Mac này) hoặc `0.0.0.0` (chia sẻ proxy cho các thiết bị khác trong cùng mạng LAN, tự động nhận diện địa chỉ IP LAN).
- **Badge Bật/Tắt Nhanh**: Badge SOCKS5 hiển thị trực tiếp trên từng hàng Server, click để bật/tắt tức thì không cần mở form chỉnh sửa.
- **Xử Lý Xung Đột Cổng Thông Minh**: Nếu cổng SOCKS5 bị trùng (`Address already in use`), macSSH sẽ tự động tắt proxy an toàn, thông báo qua popup Toast 5s glassmorphic mà không làm gián đoạn phiên SSH chính.

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

### 📊 5. Bảng Quản Lý Truyền Tải & Log Console Thời Gian Thực
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

### 🌐 8. Hỗ Trợ Đa Ngôn Ngữ (Localization L10N)
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

### 1. Tải Bản Cài Đặt DMG
Tải phiên bản mới nhất `macSSH_Universal_x.x.x.dmg` từ mục [GitHub Releases](https://github.com/devduong/macSSH/releases).

### 2. Cài Đặt Ứng Dụng
Mở tệp `.dmg` đã tải về và kéo biểu tượng **macSSH.app** vào thư mục **Applications** (`/Applications`).

### 3. Mở Ứng Dụng Lần Đầu & Bỏ Qua Cảnh Báo macOS Gatekeeper

> [!WARNING]
> **Cảnh báo (Warning)**  
> Do macSSH là phần mềm mã nguồn mở miễn phí và không sử dụng chứng chỉ ký trả phí của Apple Developer, macOS Gatekeeper có thể hiển thị cảnh báo: *"macSSH cannot be opened because the developer cannot be verified"* hoặc *"macOS cannot verify that this app is free from malware"*.

Để mở ứng dụng:
1. Mở **System Settings** (Cài đặt hệ thống) trên máy Mac của bạn.
2. Chọn mục **Privacy & Security** (Quyền riêng tư & Bảo mật).
3. Cuộn xuống phần **Security** (Bảo mật).
4. Nhấn vào nút **"Open Anyway"** (Mở dù sao đi nữa) bên cạnh thông báo macSSH bị chặn.
5. Trong hộp thoại xác nhận, nhấn **"Open"** (Mở) và nhập mật khẩu máy Mac hoặc dùng Touch ID.

*(Cách khác: Nhấp chuột phải / Control-click vào `macSSH.app` trong Finder -> chọn **Open** -> nhấn **Open**).*

---

### Biên Dịch Từ Mã Nguồn (Build from Source)

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

3. **Biên dịch và đóng gói DMG chuẩn hóa bằng script**:
   ```bash
   ./create-dmg.sh
   ```
   *Script sẽ tự động build bản Release Universal (arm64 + x86_64), ký số ad-hoc, tạo file DMG và xuất bản chạy tại `build/macSSH.app`.*

4. **Khởi chạy ứng dụng**:
   ```bash
   open build/macSSH.app
   ```

---

## ☕ Ủng Hộ Dự Án (Donate)

**macSSH** là dự án mã nguồn mở phi lợi nhuận được phát triển với mục tiêu mang lại công cụ làm việc tốt nhất cho cộng đồng macOS. Nếu bạn thấy macSSH hữu ích cho công việc hàng ngày, hãy ủng hộ tác giả một tách cà phê để tiếp tục duy trì và phát triển dự án nhé! ❤️

### 1. Hỗ Trợ Qua Ko-fi & GitHub
- ☕ **Ko-fi**: [https://ko-fi.com/X4P324ZPZ3](https://ko-fi.com/X4P324ZPZ3)
- ⭐ **Tặng 1 sao trên GitHub**: [devduong/macSSH](https://github.com/devduong/macSSH)

### 2. Ủng Hộ Qua Tiền Điện Tử (Crypto Donation)
Bạn có thể gửi bất kỳ token nào thuộc mạng **BNB Smart Chain (BEP20)** như *USDT, BNB, BUSD, USDC...* đến địa chỉ ví dưới đây:

- **Mạng lưới (Network)**: `BEP20 (BSC – Binance Smart Chain)`
- **Địa chỉ ví (Wallet Address)**:
  ```text
  0xe26c0DC422EF744816Ca3B2d210e6214fdC4e18E
  ```

---

## 🙏 Lời Cảm Ơn & Credits

- 🌟 **Gửi lời cảm ơn đặc biệt đến anh [macnev2013](https://github.com/macnev2013)** — Tác giả của dự án `macSCP` và `anySCP`. Cảm ơn anh rất nhiều vì ý tưởng thiết kế tuyệt vời ban đầu, là nguồn cảm hứng lớn và nền tảng quý giá để xây dựng nên dự án **macSSH**.
- 🚀 [Citadel](https://github.com/Orlandos-nl/Citadel) bởi Joannis Orlandos & [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh) bởi Apple — Thư viện giao thức SSH & SFTP cốt lõi.
- 💻 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) bởi Miguel de Icaza — Trình giả lập Terminal mạnh mẽ trên macOS.
- 🎨 [SF Symbols](https://developer.apple.com/sf-symbols/) bởi Apple — Hệ thống biểu tượng giao diện chuẩn macOS.

---

## 📄 Giấy Phép (License)

Dự án được phân phối dưới giấy phép **MIT License** — Xem tệp [LICENSE](../LICENSE) để biết thêm chi tiết.

---

<p align="center">
  Được tạo ra với ❤️ dành cho cộng đồng người dùng macOS.
</p>
