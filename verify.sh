#!/usr/bin/env bash
# Kiểm tra cấu hình CachyOS + niri trên Acer Nitro 5 AN515-57
set -uo pipefail

pass=0; fail=0; warnc=0
ok()   { printf '  \033[1;32m[ OK ]\033[0m %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  \033[1;31m[FAIL]\033[0m %s\n' "$*"; fail=$((fail+1)); }
warn() { printf '  \033[1;33m[WARN]\033[0m %s\n' "$*"; warnc=$((warnc+1)); }
section() { printf '\n\033[1;34m%s\033[0m\n' "$*"; }

section "1. Session / compositor"
if [ "${XDG_CURRENT_DESKTOP:-}" = "niri" ] || [ -n "${NIRI_SOCKET:-}" ]; then
  ok "đang chạy trong niri"
else
  warn "không phải session niri (XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-unset})"
fi
command -v niri >/dev/null && ok "niri $(niri --version 2>/dev/null)" || bad "không có niri"

section "2. GPU / render device"
mapfile -t renders < <(ls /dev/dri/by-path/*-render 2>/dev/null)
[ "${#renders[@]}" -ge 2 ] && ok "thấy ${#renders[@]} render node" || warn "chỉ thấy ${#renders[@]} render node"
for r in "${renders[@]}"; do printf '        %s -> %s\n' "$(basename "$r")" "$(readlink -f "$r" | xargs basename)"; done
printf '        '; lspci -s 00:02.0 2>/dev/null | sed 's/^[0-9a-f:.]* //'
printf '        '; lspci -s 01:00.0 2>/dev/null | sed 's/^[0-9a-f:.]* //'

if grep -q 'render-drm-device' "$HOME/.config/niri/config.kdl" 2>/dev/null; then
  dev=$(grep -oP 'render-drm-device\s+"\K[^"]+' "$HOME/.config/niri/config.kdl" | head -1)
  ok "config đang ép render: $dev"
  if [ "$dev" = "/dev/dri/renderD129" ]; then
    ok "đúng Intel iGPU (renderD129) — tốt cho pin"
  else
    warn "không phải renderD129 — kiểm tra lại mapping ở trên"
  fi
else
  bad "config chưa có render-drm-device -> có thể render bằng NVIDIA"
fi

section "3. NVIDIA power state"
for c in /sys/class/drm/card[0-9]; do
  name=$(basename "$(readlink -f "$c/device")")
  st=$(cat "$c/device/power_state" 2>/dev/null)
  [ "$name" = "0000:01:00.0" ] && { [ "$st" = "D3cold" ] && ok "NVIDIA đang ngủ (D3cold)" || warn "NVIDIA ở $st (nên là D3cold)"; }
done
if command -v nvidia-smi >/dev/null; then
  nvidia-smi --query-gpu=name,driver_version,memory.used --format=csv,noheader 2>/dev/null \
    | sed 's/^/        /' || warn "nvidia-smi lỗi"
else
  warn "chưa có nvidia-smi"
fi

section "4. sched-ext"
st=$(cat /sys/kernel/sched_ext/state 2>/dev/null || echo missing)
[ "$st" = "enabled" ] && ok "sched_ext đang bật" || warn "sched_ext: $st"
systemctl is-active scx_loader >/dev/null 2>&1 && ok "scx_loader active" || warn "scx_loader không active"

section "5. Kernel / repo"
ok "kernel $(uname -r)"
grep -q '^\[cachyos' /etc/pacman.conf 2>/dev/null && ok "đã có repo CachyOS" || warn "không thấy repo CachyOS"
printf '        glibc hwcaps: '; /lib/ld-linux-x86-64.so.2 --help 2>/dev/null | grep -o 'x86-64-v[34]' | sort -u | tr '\n' ' '; echo

section "6. Hiển thị / VRR"
if command -v niri >/dev/null && [ -n "${NIRI_SOCKET:-}" ]; then
  niri msg outputs 2>/dev/null | grep -E 'Output|Current mode|VRR|Variable' | sed 's/^/        /'
else
  warn "không trong niri — bỏ qua niri msg outputs"
fi

section "7. Audio"
codec=$(grep -m1 '^Codec:' /proc/asound/card*/codec#0 2>/dev/null | head -1 | sed 's/^Codec: //')
[ -n "$codec" ] && ok "codec: $codec" || warn "không đọc được codec"
[ -f /etc/modprobe.d/99-acer-audio.conf ] && ok "quirk ALC295 đang bật" || warn "quirk ALC295 chưa bật (chỉ bật nếu lỗi tai nghe)"
systemctl is-active --quiet wireplumber && ok "wireplumber active" || bad "wireplumber không chạy"

section "8. Mạng / Bluetooth"
ip -br link 2>/dev/null | grep -E '^wl|^en' | sed 's/^/        /'
systemctl is-active --quiet bluetooth && ok "bluetooth active" || warn "bluetooth không chạy"

section "9. Điện / nhiệt"
command -v powerprofilesctl >/dev/null && ok "profile: $(powerprofilesctl get 2>/dev/null)" || warn "không có power-profiles-daemon"
cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "        thermal_zone0: %.1f°C\n", $1/1000}'
swapon --show 2>/dev/null | sed 's/^/        /'

section "10. Snapper / rollback"
sudo -n snapper -c root list >/dev/null 2>&1 && ok "snapper root OK" \
  || warn "không kiểm tra được snapper (cần sudo) hoặc chưa cấu hình"

printf '\n\033[1mTổng: %d OK, %d WARN, %d FAIL\033[0m\n' "$pass" "$warnc" "$fail"
[ "$fail" -eq 0 ] && exit 0 || exit 1
