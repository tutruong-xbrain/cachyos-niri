# CachyOS + niri — cấu hình cho Acer Nitro 5 AN515-57

> ⚠️ **SAO LƯU THƯ MỤC NÀY RA USB/CLOUD TRƯỚC KHI CÀI.** Cài CachyOS sẽ xoá
> toàn bộ ổ NVMe, kể cả `/home/tutruong/Work`.

---

## 0. Profile phần cứng (đã kiểm tra thực tế)

| Thành phần | Giá trị | Dùng cho cấu hình |
|---|---|---|
| Máy | Acer Nitro 5 AN515-57 | |
| CPU | i5-11400H (Tiger Lake-H, có AVX-512) | repo **x86-64-v3** (khuyến nghị) |
| iGPU | Intel UHD — PCI `00:02.0` | `/dev/dri/renderD129` |
| dGPU | RTX 3060 Mobile — PCI `01:00.0` | `/dev/dri/renderD128`, `nvidia-open` |
| eDP-1 | 1920x1080@144.003 | màn trong |
| DP-2 | 2560x1440@143.998 | màn ngoài (qua Intel/USB-C) |
| Audio | Realtek ALC295 + NVIDIA HDMI | quirk `alc295-headset` nếu lỗi |
| Wi-Fi | Intel AX201 (`iwlwifi`) | OK |
| LAN | Killer E2600 (`r8169`) | OK |
| Touchpad | ELAN0521 (I2C-HID) | OK |
| Boot | UEFI, Secure Boot OFF, TPM2 | không cần ký module |
| Swap | zram | giữ zram, không cần swapfile |

---

## 1. Chọn gì trong installer (Calamares)

| Bước | Chọn |
|---|---|
| Desktop Environment | **Niri** |
| Kernel | **linux-cachyos** (đừng chọn `-rt`) |
| Filesystem | **Btrfs** + bật **Snapper** |
| Encryption | **LUKS** (giữ như hiện tại) |
| Bootloader | **Limine** nếu có, không thì **systemd-boot** |
| NVIDIA | **nvidia-open** (RTX 3060 = Turing+) |
| Secure Boot | **Tắt** (đang tắt sẵn — tránh phải ký module) |
| Extra | bật `cachyos-settings`, `ananicy-cpp`, `zram` |

Sau khi cài xong, chạy:

```bash
cd ~/cachyos-niri   # sau khi copy từ USB về
chmod +x post-install.sh verify.sh
./post-install.sh
```

Rồi logout → chọn session **Niri**.

---

## 2. Ba điểm dễ lỗi nhất trên máy này

### 2.1 Hybrid GPU — compositor phải chạy trên Intel
`config/niri/config.kdl` đã đặt:
```kdl
debug { render-drm-device "/dev/dri/renderD129" }
```
Kiểm tra sau reboot:
```bash
cat /sys/class/drm/card*/device/power_state   # NVIDIA phải là D3cold
nvidia-smi                                     # phải thấy GPU nhưng 0% util
```
Nếu số renderD thay đổi (hiếm), sửa lại theo:
```bash
ls -l /dev/dri/by-path/*-render
lspci -s 00:02.0   # Intel
```

Chạy app bằng dGPU:
```bash
prime-run <app>
# hoặc
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia <app>
```

### 2.2 Cổng HDMI đi qua NVIDIA → **niri không xuất được ra HDMI**
Trên AN515-57:
- **USB-C / Thunderbolt → Intel** → dùng được với niri (đây là cổng bạn đang cắm DP-2).
- **HDMI → NVIDIA** → niri chạy trên Intel **không** đẩy hình ra được (niri không hỗ trợ multi-GPU output).

→ Nếu cần HDMI: chạy niri hoàn toàn trên NVIDIA (`renderD128`) và chấp nhận nóng/pin tụt,
hoặc dùng cáp USB-C → DP/HDMI.

### 2.3 Audio ALC295
Nếu jack tai nghe/mic không nhận, bật quirk trong `post-install.sh`
(biến `ENABLE_ACER_AUDIO_QUIRK=1`) rồi reboot.

---

## 3. Bảng rủi ro & cách xử lý

| Rủi ro | Dấu hiệu | Xử lý |
|---|---|---|
| niri render nhầm NVIDIA | nóng, pin tụt, `power_state` = D0 | sửa `render-drm-device` |
| Suspend chết màn hình | resume đen | bật `nvidia-suspend/resume` (script lo) |
| Tearing/giật 144Hz | | bật VRR cho DP-2, tắt VRR cho eDP-1 |
| Tai nghe không tiếng | | quirk ALC295 |
| Fan ồn / nóng | | `nbfc-linux` (AUR) hoặc `powerprofilesctl set balanced` |
| Update vỡ config | | `sudo snapper -c root list` → rollback |
| App X11 không mở | | `xwayland-satellite` (script cài) |
| Screen share trắng | | portal-gnome + portal-gtk (script cài) |
| AVX-512 làm nóng | nhiệt cao khi build | dùng repo v3 thay vì v4 |
| `tlp` + PPD đánh nhau | pin tệ | **chỉ dùng một** (script dùng PPD) |

---

## 4. Cấu trúc file

```
cachyos-niri/
├── README.md                  # file này
├── post-install.sh            # cài gói + tweak hệ thống
├── verify.sh                  # kiểm tra sau khi cài
├── flash-usb.sh               # ghi ISO ra USB (chạy bằng sudo)
├── theme.sh                   # font, icon, cursor, ghostty, matugen
└── config/
    ├── niri/config.kdl        # config custom Omarchy-style (NIRI_MODE=full)
    ├── niri/hardware.kdl      # CHỈ phần cứng — include vào config CachyOS
    ├── niri/pretty.kdl        # snippet giao diện — SỬA TAY, không include
    ├── environment.d/10-wayland.conf
    ├── modprobe.d/99-nvidia.conf
    ├── modprobe.d/99-acer-audio.conf
    ├── zram-generator.conf    # -> /etc/systemd/zram-generator.conf
    ├── sysctl.d/99-laptop.conf
    └── nvidia-profiles/50-niri-vram.json
```

### Chọn kiểu cấu hình niri

CachyOS đã cài sẵn `cachyos-niri-settings` + `cachyos-niri-noctalia`
(config + theme + keybind + Noctalia). Mặc định script **không ghi đè**:

```bash
./post-install.sh                     # giữ config CachyOS + include hardware.kdl  ← khuyến nghị
NIRI_MODE=full ./post-install.sh      # thay bằng config custom Omarchy-style
```

- `hardware` (mặc định): giữ theme/keybind/Noctalia của CachyOS, chỉ thêm
  render device + output. Ít rủi ro nhất.
- `full`: dùng `config/niri/config.kdl` của repo — keybind kiểu Omarchy,
  tự set mọi thứ. Config cũ luôn được backup trước khi ghi đè.

---

## 5. Giao diện ("đẹp") — tương thích Intel UHD + 2 màn 144Hz

`post-install.sh` tự chạy `theme.sh` (tắt bằng `PRETTY=0`). Nó cài:

| Thành phần | Gói |
|---|---|
| Font UI | `inter-font` |
| Font terminal | `ttf-jetbrains-mono-nerd` |
| Icon | `papirus-icon-theme` |
| GTK theme | `adw-gtk-theme` |
| Terminal | `ghostty` (+ config sẵn) |
| Wallpaper daemon | `wpaperd` |
| Sinh màu từ ảnh | `matugen` |
| Cursor (AUR, optional) | `bibata-cursor-theme` |

### Giới hạn phần cứng cần nhớ

- **niri không có blur** — đừng tìm hiệu ứng mờ, không tồn tại.
- Intel UHD gánh 2 màn 144Hz → giữ `shadow softness ≤ 24`, animation ≤ 300ms.
  `pretty.kdl` đã đặt sẵn mức an toàn.
- **`pretty.kdl` KHÔNG được include tự động.** Config CachyOS đã có block
  `layout {}`, `animations {}`, `window-rule {}`; include thêm sẽ lỗi trùng
  section. Muốn dùng thì mở `~/.config/niri/config.kdl`, thay giá trị trong
  block tương ứng bằng giá trị trong `pretty.kdl`, rồi `niri validate`.

### Theme màu

Cách nhanh nhất: dùng Noctalia → Settings → Wallpaper → chọn ảnh, nó tự
đồng bộ màu sang bar/launcher. `matugen` chỉ hữu ích nếu bạn tự viết template
(`~/.config/matugen/config.toml`).



---

## 6. Thứ tự làm

1. Copy thư mục này ra USB.
2. Cài CachyOS theo mục 1.
3. Copy thư mục về `~/cachyos-niri`.
4. `./post-install.sh` (tự chạy cả `theme.sh`).
5. Reboot, đăng nhập Niri.
6. `./verify.sh` — phải xanh hết.
7. Chọn wallpaper trong Noctalia (mục 5) → nó tự sync màu.
8. Nếu muốn gaps/shadow/animation: đối chiếu `pretty.kdl` rồi sửa tay.
9. Chỉnh `~/.config/niri/config.kdl` theo thói quen (layout "us" → "vn" nếu cần).

---

## 7. Việc cần làm ngay sau khi vào niri

```bash
# 1. Đổi wallpaper (config đang trỏ /home/tutruong/Pictures/wallpaper.jpg)
# 2. Kiểm tra tên output + mode thật
niri msg outputs

# 3. Noctalia: mở app, vào Settings → Templates → niri → Apply
#    để nó tự đồng bộ theme (màu, font) vào config niri.
#    Binary tên là `noctalia` (không phải noctalia-shell).

# 4. Nếu dùng bàn phím tiếng Việt, sửa trong config:
#    xkb { layout "us" }  ->  xkb { layout "us,vn" options "grp:alt_shift_toggle" }
```

Kiểm tra lại toàn bộ: `niri validate` (báo lỗi cú pháp KDL trước khi reload).

---

## 8. Nếu sau này muốn quay lại Omarchy

Không cần cài lại: Omarchy chỉ là bộ config trên Arch. Nhưng đơn giản nhất là
giữ một snapshot Btrfs trước khi đổi, hoặc cài lại từ ISO Omarchy.

