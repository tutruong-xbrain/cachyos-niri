#!/usr/bin/env bash
# ============================================================
#  Backup toàn bộ dữ liệu cá nhân trước khi cài lại OS
#  Dùng:  ./backup-home.sh [thư-mục-đích]
# ============================================================
set -uo pipefail

DEST="${1:-$HOME/Downloads}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$DEST/home-backup-$STAMP.tar.zst"

ok()   { printf '\033[1;32m[+] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }

mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

add() {
  local src="$1"
  [ -e "$src" ] || return 0
  mkdir -p "$TMP/$(dirname "${src#"$HOME"/}")" 2>/dev/null
  cp -a "$src" "$TMP/${src#"$HOME"/}" 2>/dev/null && ok "$(basename "$src")"
}

echo "== SSH / GPG / git =="
add "$HOME/.ssh"
add "$HOME/.gnupg"
add "$HOME/.gitconfig"
add "$HOME/.config/git"
add "$HOME/.config/gh"

echo "== shell =="
add "$HOME/.bashrc"
add "$HOME/.zshrc"
add "$HOME/.profile"
add "$HOME/.bash_profile"

echo "== dữ liệu =="
add "$HOME/Work"
add "$HOME/Documents"
add "$HOME/Pictures"
add "$HOME/Videos"
add "$HOME/Music"
add "$HOME/Desktop"

echo "== keyring =="
add "$HOME/.local/share/keyrings"

echo "== backup trình duyệt (nếu có) =="
for f in "$HOME"/Downloads/browser-backup-*.tar.zst; do
  [ -f "$f" ] && cp -a "$f" "$TMP/" && ok "$(basename "$f")"
done

echo
echo "== đang nén =="
tar --zstd -cf "$OUT" -C "$TMP" . && \
  ok "Xong: $OUT ($(du -h "$OUT" | cut -f1))" || \
  { warn "nén lỗi"; exit 1; }

cat <<EOF

────────────────────────────────────────────────────────────
 $OUT

 ⚠️  File này CHỨA SSH PRIVATE KEY và token GitHub.
     - Đừng upload lên chỗ công khai.
     - Nếu upload cloud, nên mã hoá trước:
         gpg -c "$OUT"
       (nhập mật khẩu, sẽ tạo file .gpg)

 Copy ra ngoài TRƯỚC khi cài CachyOS.
────────────────────────────────────────────────────────────
EOF
