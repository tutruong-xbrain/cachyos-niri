#!/usr/bin/env bash
# ============================================================
#  CachyOS + niri — post-install cho Acer Nitro 5 AN515-57
#  i5-11400H / Intel UHD / RTX 3060 Mobile / AX201 / ALC295
#
#  Chạy bằng user thường (có sudo), KHÔNG chạy bằng root.
#  Biến môi trường:
#    ENABLE_ACER_AUDIO_QUIRK=1  -> bật quirk ALC295 nếu lỗi tai nghe
# ============================================================
set -uo pipefail

ENABLE_ACER_AUDIO_QUIRK="${ENABLE_ACER_AUDIO_QUIRK:-0}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

msg()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[+] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*"; exit 1; }

[ "$(id -u)" -eq 0 ] && die "Đừng chạy bằng root. Chạy: ./post-install.sh"
command -v pacman >/dev/null || die "Không phải Arch/CachyOS?"

# ------------------------------------------------------------
msg "1/9  Cập nhật hệ thống"
sudo pacman -Syu --noconfirm || warn "pacman -Syu có lỗi — kiểm tra mirror trước khi tiếp tục"

# ------------------------------------------------------------
msg "2/9  Gói nền cho niri"
BASE_PKGS=(
  niri xwayland-satellite
  fuzzel mako waybar swaybg swayidle swaylock
  grim slurp satty wl-clipboard cliphist
  xdg-desktop-portal-gtk xdg-desktop-portal-gnome
  udiskie polkit-gnome gnome-keyring
  brightnessctl playerctl pavucontrol
  upower ddcutil
  noto-fonts noto-fonts-emoji ttf-jetbrains-mono-nerd
  btop fastfetch git base-devel
)
sudo pacman -S --needed --noconfirm "${BASE_PKGS[@]}" \
  || warn "Một số gói không cài được — xem lại tên gói ở trên"

# Noctalia (all-in-one shell) — có trong repo Arch/CachyOS
sudo pacman -S --needed --noconfirm noctalia 2>/dev/null \
  || warn "Không cài được 'noctalia' — dùng waybar + mako thay thế"

# ------------------------------------------------------------
msg "3/9  NVIDIA (RTX 3060 Mobile)"
if pacman -Qq 2>/dev/null | grep -qE '^(nvidia-open(-dkms)?|nvidia(-dkms)?)$'; then
  ok "Đã có driver NVIDIA, bỏ qua"
else
  warn "Chưa có driver NVIDIA — cài nvidia-open-dkms"
  sudo pacman -S --needed --noconfirm \
    linux-cachyos-headers nvidia-open-dkms \
    nvidia-utils lib32-nvidia-utils nvidia-prime nvidia-settings \
    || warn "Cài NVIDIA lỗi — cài lại từ cachyos-hello (mục NVIDIA)"
fi

# ------------------------------------------------------------
msg "4/9  Dịch vụ hệ thống"
for svc in bluetooth fstrim.timer power-profiles-daemon thermald scx_loader; do
  if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
    sudo systemctl enable --now "$svc" 2>/dev/null && ok "bật $svc" || warn "không bật được $svc"
  else
    warn "không có unit $svc"
  fi
done

# NVIDIA suspend/resume (máy không hỗ trợ S0ix -> dùng S3)
for svc in nvidia-suspend nvidia-resume nvidia-hibernate; do
  sudo systemctl enable "$svc.service" 2>/dev/null && ok "bật $svc"
done

# ------------------------------------------------------------
msg "5/9  sched-ext (scx_lavd cho laptop)"
sudo pacman -S --needed --noconfirm scx-scheds 2>/dev/null \
  || warn "Không có gói scx-scheds — bỏ qua sched-ext"
if [ -f /etc/scx_loader/config.toml ]; then
  sudo sed -i 's/^default_sched *=.*/default_sched = "scx_lavd"/' /etc/scx_loader/config.toml 2>/dev/null || true
fi
sudo systemctl restart scx_loader 2>/dev/null || true

# ------------------------------------------------------------
msg "6/9  Copy cấu hình"
mkdir -p "$HOME/.config/niri" "$HOME/.config/environment.d" "$HOME/Pictures/Screenshots"

if [ -f "$HOME/.config/niri/config.kdl" ]; then
  cp "$HOME/.config/niri/config.kdl" "$HOME/.config/niri/config.kdl.bak.$(date +%s)"
  warn "Đã backup config niri cũ"
fi
install -Dm644 "$HERE/config/niri/config.kdl" "$HOME/.config/niri/config.kdl"
install -Dm644 "$HERE/config/environment.d/10-wayland.conf" "$HOME/.config/environment.d/10-wayland.conf"
sudo install -Dm644 "$HERE/config/modprobe.d/99-nvidia.conf" /etc/modprobe.d/99-nvidia.conf
sudo install -Dm644 "$HERE/config/zram-generator.conf" /etc/systemd/zram-generator.conf
sudo install -Dm644 "$HERE/config/sysctl.d/99-laptop.conf" /etc/sysctl.d/99-laptop.conf
sudo mkdir -p /etc/nvidia/nvidia-application-profiles-rc.d
sudo install -Dm644 "$HERE/config/nvidia-profiles/50-niri-vram.json" \
  /etc/nvidia/nvidia-application-profiles-rc.d/50-niri-vram.json

if [ "$ENABLE_ACER_AUDIO_QUIRK" = "1" ]; then
  sudo install -Dm644 "$HERE/config/modprobe.d/99-acer-audio.conf" /etc/modprobe.d/99-acer-audio.conf
  ok "Đã bật quirk audio ALC295"
else
  warn "Chưa bật quirk audio (bật sau bằng: ENABLE_ACER_AUDIO_QUIRK=1 ./post-install.sh)"
fi

# ------------------------------------------------------------
msg "7/9  Snapper (rollback Btrfs)"
if ! sudo snapper -c root list >/dev/null 2>&1; then
  warn "Chưa có snapper config 'root'."
  warn "Nếu lúc cài đã chọn Btrfs + Snapper thì bỏ qua."
  warn "Nếu chưa:  sudo snapper -c root create-config /  &&  sudo pacman -S snap-pac"
else
  ok "Snapper đã sẵn sàng"
  sudo pacman -S --needed --noconfirm snap-pac 2>/dev/null || true
fi

# ------------------------------------------------------------
msg "8/9  zram + sysctl"
sudo systemctl daemon-reload
sudo systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || true
sudo sysctl --system >/dev/null 2>&1 || true

# ------------------------------------------------------------
msg "9/9  Kiểm tra nhanh"
printf '  renderD map : '; ls -l /dev/dri/by-path/*-render 2>/dev/null | awk '{print $9, $11}' | tr '\n' ' '; echo
printf '  sched_ext   : '; cat /sys/kernel/sched_ext/state 2>/dev/null || echo n/a
printf '  nvidia      : '; (nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || echo "chưa load")
printf '  audio codec : '; grep -m1 '^Codec:' /proc/asound/card*/codec#0 2>/dev/null || echo n/a

cat <<'EOF'

────────────────────────────────────────────────────────────
 Xong. Việc còn lại:
   1) Reboot
   2) Đăng nhập session "Niri"
   3) Chạy ./verify.sh  → phải xanh hết
   4) Sửa ~/.config/niri/config.kdl nếu cần (layout "vn", wallpaper)

 Lưu ý máy này:
   • Compositor phải chạy Intel: renderD129 (đã set sẵn)
   • HDMI đi qua NVIDIA -> niri KHÔNG xuất ra HDMI được
     (dùng USB-C/Thunderbolt -> DP thay thế)
────────────────────────────────────────────────────────────
EOF
