#!/usr/bin/env bash
# ============================================================
#  Giao diện cho niri — Acer Nitro 5 AN515-57
#  Font + icon + cursor + terminal + theme GTK
#
#  Chạy:  ./theme.sh
#  (gọi sudo bên trong, không cần chạy bằng root)
# ============================================================
set -uo pipefail

msg()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[+] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }

[ "$(id -u)" -eq 0 ] && { echo "Chạy bằng user thường, đừng dùng sudo."; exit 1; }

# ------------------------------------------------------------
msg "1/5  Gói giao diện"
PKGS=(
  inter-font
  ttf-jetbrains-mono-nerd
  noto-fonts
  noto-fonts-emoji
  papirus-icon-theme
  adw-gtk-theme
  matugen
  wpaperd
  ghostty
)
sudo pacman -S --needed --noconfirm "${PKGS[@]}" \
  || warn "Một số gói lỗi — kiểm tra tên ở trên"

# Cursor Bibata (AUR) — không bắt buộc
if pacman -Qq bibata-cursor-theme >/dev/null 2>&1; then
  ok "đã có Bibata cursor"
elif command -v paru >/dev/null 2>&1; then
  paru -S --needed --noconfirm bibata-cursor-theme 2>/dev/null \
    && ok "đã cài Bibata cursor" || warn "không cài được Bibata (bỏ qua)"
else
  warn "chưa có paru -> bỏ qua Bibata cursor"
fi

# ------------------------------------------------------------
msg "2/5  Ghostty config"
mkdir -p "$HOME/.config/ghostty"
if [ -f "$HOME/.config/ghostty/config" ]; then
  cp "$HOME/.config/ghostty/config" "$HOME/.config/ghostty/config.bak.$(date +%s)"
  warn "đã backup ghostty config cũ"
fi
cat > "$HOME/.config/ghostty/config" <<'EOF'
# Ghostty — cấu hình cho niri / Nitro 5
font-family = JetBrainsMono Nerd Font
font-size = 11
font-thicken = true

# Trong suốt nhẹ (niri không có blur nên đừng đặt quá thấp)
background-opacity = 0.94

window-padding-x = 10
window-padding-y = 10
window-padding-balance = true
window-decoration = false

cursor-style = block
cursor-style-blink = false
mouse-hide-while-typing = true

copy-on-select = clipboard
confirm-close-surface = false

# Theme có sẵn của Ghostty
theme = catppuccin-mocha
EOF
ok "ghostty config xong"

# ------------------------------------------------------------
msg "3/5  GTK + icon + font"
for v in 3.0 4.0; do
  mkdir -p "$HOME/.config/gtk-$v"
  cat > "$HOME/.config/gtk-$v/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Inter 11
gtk-cursor-theme-name=Bibata-Modern-Ice
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
EOF
done
ok "gtk-3.0 + gtk-4.0 settings.ini"

if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface font-name 'Inter 11' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Ice' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface cursor-size 24 2>/dev/null || true
  ok "gsettings đã set"
fi

# ------------------------------------------------------------
msg "4/5  Wallpaper + matugen"
mkdir -p "$HOME/Pictures/Wallpapers"
WP="$HOME/Pictures/Wallpapers/wallpaper.jpg"
if [ ! -f "$WP" ]; then
  warn "Chưa có $WP"
  warn "Copy 1 ảnh vào đó rồi chạy lại, hoặc:"
  warn "  matugen image /duong/dan/anh.jpg --mode dark"
else
  if command -v matugen >/dev/null 2>&1; then
    matugen image "$WP" --mode dark 2>/dev/null && ok "matugen đã sinh bảng màu" \
      || warn "matugen lỗi (cần config templates — xem README)"
  fi
fi

# ------------------------------------------------------------
msg "5/5  Kiểm tra"
printf '  fonts Inter      : '; fc-list 2>/dev/null | grep -ci 'Inter' || echo 0
printf '  JetBrainsMono    : '; fc-list 2>/dev/null | grep -ci 'JetBrainsMono Nerd' || echo 0
printf '  Papirus icon     : '; [ -d /usr/share/icons/Papirus-Dark ] && echo yes || echo no
printf '  ghostty          : '; command -v ghostty >/dev/null && ghostty --version 2>/dev/null | head -1 || echo no

cat <<'EOF'

────────────────────────────────────────────────────────────
 Xong phần giao diện.

 Việc còn lại (làm trong Noctalia):
   1. Mở Noctalia → Settings → Wallpaper → chọn ảnh
   2. Noctalia tự sync màu sang bar/launcher
   3. Muốn gaps/shadow/animation đẹp hơn:
      mở ~/.config/niri/config.kdl, đối chiếu với
      ~/.config/niri/pretty.kdl rồi sửa tay
      (đừng include, sẽ lỗi trùng block)

 Lưu ý phần cứng:
   • Intel UHD + 2 màn 144Hz -> giữ shadow nhẹ (softness 24)
   • niri không có blur
────────────────────────────────────────────────────────────
EOF
