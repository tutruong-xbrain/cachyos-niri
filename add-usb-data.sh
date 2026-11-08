#!/usr/bin/env bash
# ============================================================
#  Thêm phân vùng dữ liệu vào USB bộ cài CachyOS
#  để chứa file backup (USB MBR: thêm partition không ảnh hưởng boot)
#
#  Dùng:  sudo ./add-usb-data.sh [/dev/sda]
# ============================================================
set -euo pipefail

DEV="${1:-/dev/sda}"
SRC="$HOME/Downloads"

msg()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[+] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Phải chạy bằng sudo:  sudo ./add-usb-data.sh"
[ -b "$DEV" ] || die "Không phải block device: $DEV"

# --- kiểm tra đúng USB bộ cài ---
PTTYPE=$(lsblk -dno PTTYPE "$DEV")
[ "$PTTYPE" = "dos" ] || die "Bảng phân vùng là '$PTTYPE', script này chỉ hỗ trợ MBR (dos)"
lsblk -no LABEL "$DEV" | grep -q 'COS_' || die "Không thấy nhãn COS_* — không phải USB CachyOS?"
ok "Đúng USB CachyOS ($DEV, MBR)"

# --- đã có partition 3 chưa ---
if parted -s -m "$DEV" unit B print | awk -F: '$1=="3"{found=1} END{exit !found}'; then
  die "$DEV đã có phân vùng 3 — không làm gì thêm"
fi

# --- tìm chỗ trống ---
END2=$(parted -s -m "$DEV" unit B print | awk -F: '$1=="2"{print $3}' | tr -d 'B')
[ -n "$END2" ] || die "Không đọc được phân vùng 2"
START=$(( END2 + 1048576 ))   # căn 1 MiB
DEVSIZE=$(blockdev --getsize64 "$DEV")
FREE=$(( DEVSIZE - START ))
[ "$FREE" -gt $((500*1024*1024)) ] || die "Không đủ chỗ trống (chỉ $((FREE/1024/1024)) MB)"
ok "Chỗ trống: $((FREE/1024/1024/1024)) GB"

cat <<EOF

  Sẽ tạo:
    $DEV 3   FAT32   nhãn BACKUP   từ byte $START đến hết đĩa

  Phân vùng 1 (ISO) và 2 (EFI) KHÔNG bị đụng tới.
  Boot vẫn hoạt động bình thường.

EOF
read -rp 'Gõ "YES" để tiếp tục: ' ans
[ "$ans" = "YES" ] || die "Đã huỷ"

# --- tạo + format ---
msg "Tạo phân vùng 3"
parted -s "$DEV" unit B mkpart primary fat32 "${START}B" 100%
partprobe "$DEV" 2>/dev/null || true
sleep 1

PART="${DEV}3"
[ -b "$PART" ] || die "Không thấy $PART sau khi tạo"

msg "Format FAT32"
mkfs.vfat -F 32 -n BACKUP "$PART" >/dev/null
ok "đã format"

# --- mount + copy ---
MNT=$(mktemp -d)
mount "$PART" "$MNT"

msg "Copy backup"
shopt -s nullglob
found=0
for f in "$SRC"/home-backup-*.tar.zst "$SRC"/browser-backup-*.tar.zst; do
  cp -a "$f" "$MNT/" && ok "$(basename "$f") ($(du -h "$f" | cut -f1))"
  found=1
done
[ "$found" -eq 1 ] || warn "Không tìm thấy file backup nào trong $SRC"

# copy luôn thư mục script
if [ -d "$HOME/Work/cachyos-niri" ]; then
  cp -a "$HOME/Work/cachyos-niri" "$MNT/" && ok "cachyos-niri/"
fi

sync
msg "Kiểm tra"
ls -lh "$MNT"
df -h "$MNT" | tail -1

umount "$MNT"
rmdir "$MNT"

msg "Xong"
lsblk -o NAME,SIZE,FSTYPE,LABEL "$DEV"
ok "Backup đã nằm trên phân vùng BACKUP của USB."
warn "Sau khi cài CachyOS: cắm USB, mount phân vùng BACKUP, copy file ra."
