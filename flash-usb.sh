#!/usr/bin/env bash
# Ghi CachyOS ISO ra USB — có kiểm tra an toàn.
# Dùng:  sudo ./flash-usb.sh [đường-dẫn-iso]
set -euo pipefail

ISO="${1:-$HOME/Downloads/cachyos/cachyos-desktop-linux-260809.iso}"

msg()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[+] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Phải chạy bằng sudo:  sudo ./flash-usb.sh"
[ -f "$ISO" ] || die "Không thấy ISO: $ISO"

ISO_SIZE=$(stat -c%s "$ISO")
ISO_MB=$((ISO_SIZE / 1024 / 1024))
msg "ISO: $ISO  (${ISO_MB} MB)"

# --- tìm USB ---
mapfile -t USBS < <(lsblk -dnpo NAME,SIZE,RM,TRAN,MODEL | awk '$3==1 && $4=="usb" {print $1}')
[ "${#USBS[@]}" -gt 0 ] || die "Không tìm thấy USB nào (RM=1, TRAN=usb)"

msg "USB đang cắm:"
i=1
for d in "${USBS[@]}"; do
  sz=$(lsblk -dnbo SIZE "$d")
  mdl=$(lsblk -dno MODEL "$d" | xargs)
  printf '  %d) %-14s %6.1f GB  %s\n' "$i" "$d" "$(awk -v s="$sz" 'BEGIN{print s/1e9}')" "$mdl"
  i=$((i+1))
done

if [ "${#USBS[@]}" -eq 1 ]; then
  DEV="${USBS[0]}"
  warn "Chỉ có 1 USB -> chọn $DEV"
else
  read -rp "Chọn số thứ tự USB: " n
  DEV="${USBS[$((n-1))]}"
fi
[ -b "$DEV" ] || die "Không phải block device: $DEV"

DEV_SIZE=$(lsblk -dnbo SIZE "$DEV")
[ "$DEV_SIZE" -ge "$ISO_SIZE" ] || die "USB ($((DEV_SIZE/1024/1024)) MB) nhỏ hơn ISO (${ISO_MB} MB)"
ok "USB $DEV — $(awk -v s="$DEV_SIZE" 'BEGIN{printf "%.1f GB", s/1e9}')"

# --- unmount ---
for p in $(lsblk -lnpo NAME "$DEV" | tail -n +2); do
  if findmnt -n "$p" >/dev/null 2>&1; then
    warn "Unmount $p"; umount "$p" || die "Không unmount được $p"
  fi
done

# --- xác nhận ---
cat <<EOF

  ┌──────────────────────────────────────────────────────────┐
  │  SẼ XOÁ TOÀN BỘ DỮ LIỆU TRÊN:  $DEV
  │  Model: $(lsblk -dno MODEL "$DEV" | xargs)
  │  Dung lượng: $(awk -v s="$DEV_SIZE" 'BEGIN{printf "%.1f GB", s/1e9}')
  │  Ghi từ: $ISO
  └──────────────────────────────────────────────────────────┘

EOF
read -rp 'Gõ chính xác "YES" để tiếp tục: ' ans
[ "$ans" = "YES" ] || die "Đã huỷ."

# --- ghi ---
msg "Đang ghi... (3-8 phút tuỳ tốc độ USB)"
dd if="$ISO" of="$DEV" bs=4M status=progress conv=fsync oflag=direct 2>&1 || \
  dd if="$ISO" of="$DEV" bs=4M status=progress conv=fsync
sync
blockdev --rereadpt "$DEV" 2>/dev/null || true

msg "Xong. Kiểm tra:"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL "$DEV"
echo
ok "USB đã sẵn sàng. Rút ra, cắm vào máy đích, boot vào BIOS chọn USB."
warn "Nhớ: boot UEFI, tắt Secure Boot nếu đang bật."
