#!/usr/bin/env bash
# ============================================================
#  Backup dữ liệu trình duyệt trước khi cài lại hệ điều hành
#
#  Dùng:
#    ./backup-browser.sh light [thư-mục-đích]   # bookmark, mật khẩu, history, extension, session
#    ./backup-browser.sh full  [thư-mục-đích]   # toàn bộ profile trừ cache
#
#  Mặc định: light, đích ~/Downloads
# ============================================================
set -uo pipefail

MODE="${1:-light}"
DEST="${2:-$HOME/Downloads}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$DEST/browser-backup-$STAMP.tar.zst"

msg()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[+] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*"; exit 1; }

mkdir -p "$DEST" || die "Không tạo được $DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- cảnh báo nếu browser đang chạy ---
for p in chromium chrome brave vivaldi opera msedge firefox; do
  if pgrep -x "$p" >/dev/null 2>&1; then
    warn "$p đang chạy — nên đóng để backup chính xác (vẫn tiếp tục)"
  fi
done

# ============================================================
#  CHROMIUM / CHROME / BRAVE / EDGE / VIVALDI / OPERA
# ============================================================
copy_chromium() {
  local src="$1" name="$2"
  [ -d "$src" ] || return 0

  local out="$TMP/$name"
  mkdir -p "$out"

  # file cấp root của profile
  for f in "Local State" "First Run"; do
    [ -f "$src/$f" ] && cp -a "$src/$f" "$out/" 2>/dev/null
  done

  local prof="$src/Default"
  [ -d "$prof" ] || prof="$(find "$src" -maxdepth 2 -name 'Preferences' -printf '%h\n' 2>/dev/null | head -1)"
  [ -d "$prof" ] || { warn "$name: không tìm thấy profile"; return 0; }

  mkdir -p "$out/$(basename "$prof")"
  local dst="$out/$(basename "$prof")"

  if [ "$MODE" = "full" ]; then
    rsync -a \
      --exclude 'Cache/' --exclude 'Code Cache/' --exclude 'GPUCache/' \
      --exclude 'DawnCache/' --exclude 'DawnGraphiteCache/' --exclude 'DawnWebGPUCache/' \
      --exclude 'GrShaderCache/' --exclude 'ShaderCache/' --exclude 'GraphiteDawnCache/' \
      --exclude 'Service Worker/' --exclude 'Shared Dictionary/' \
      --exclude 'component_crx_cache/' --exclude 'Safe Browsing/' \
      --exclude 'CertificateRevocation/' --exclude 'DeferredBrowserMetrics/' \
      --exclude 'OnDeviceHeadSuggestModel/' --exclude 'OptimizationHints/' \
      --exclude 'segmentation_platform/' --exclude 'hyphen-data/' \
      --exclude 'WasmTtsEngine/' --exclude 'WidevineCdm/' \
      --exclude 'ActorSafetyLists/' --exclude 'MEIPreload/' \
      --exclude 'Subresource Filter/' --exclude 'ZxcvbnData/' \
      --exclude 'OptimizationGuideModelDownloading/' --exclude 'Screen AI/' \
      "$prof/" "$dst/" 2>/dev/null
  else
    local items=(
      "Bookmarks" "Bookmarks.bak"
      "History" "History-journal" "History-wal" "History-shm"
      "Login Data" "Login Data-journal" "Login Data-wal" "Login Data-shm"
      "Web Data" "Web Data-journal" "Web Data-wal" "Web Data-shm"
      "Cookies" "Cookies-journal" "Cookies-wal" "Cookies-shm"
      "Preferences" "Secure Preferences" "Favicons"
      "Sessions" "Extensions" "Local Extension Settings"
      "Local Storage" "Session Storage" "IndexedDB"
      "TransportSecurity" "Network Persistent State"
    )
    local i
    for i in "${items[@]}"; do
      [ -e "$prof/$i" ] && cp -a "$prof/$i" "$dst/" 2>/dev/null
    done
  fi

  ok "$name: $(du -sh "$out" 2>/dev/null | cut -f1)"
}

copy_chromium "$HOME/.config/chromium"                "chromium"
copy_chromium "$HOME/.config/google-chrome"           "google-chrome"
copy_chromium "$HOME/.config/BraveSoftware/Brave-Browser" "brave"
copy_chromium "$HOME/.config/microsoft-edge"          "microsoft-edge"
copy_chromium "$HOME/.config/vivaldi"                 "vivaldi"
copy_chromium "$HOME/.config/opera"                   "opera"

# ============================================================
#  FIREFOX / LIBREWOLF / ZEN
# ============================================================
copy_firefox() {
  local src="$1" name="$2"
  [ -d "$src" ] || return 0
  mkdir -p "$TMP/$name"
  rsync -a \
    --exclude 'cache2/' --exclude 'startupCache/' --exclude 'shader-cache/' \
    --exclude 'datareporting/' --exclude 'crashes/' \
    "$src/" "$TMP/$name/" 2>/dev/null
  ok "$name: $(du -sh "$TMP/$name" 2>/dev/null | cut -f1)"
}

copy_firefox "$HOME/.mozilla/firefox"   "firefox"
copy_firefox "$HOME/.librewolf"         "librewolf"
copy_firefox "$HOME/.zen"               "zen"

# ============================================================
#  KEYRING — cần để giải mã mật khẩu đã lưu của Chromium
# ============================================================
if [ -d "$HOME/.local/share/keyrings" ]; then
  mkdir -p "$TMP/keyrings"
  cp -a "$HOME/.local/share/keyrings/." "$TMP/keyrings/" 2>/dev/null
  ok "keyrings: đã copy (dùng để giải mã mật khẩu)"
else
  warn "không thấy ~/.local/share/keyrings — mật khẩu Chromium có thể không giải mã được"
fi

# ============================================================
#  NÉN
# ============================================================
msg "Đang nén..."
if tar --zstd -cf "$OUT" -C "$TMP" . 2>/dev/null; then
  ok "Xong: $OUT  ($(du -h "$OUT" | cut -f1))"
else
  OUT="${OUT%.tar.zst}.tar.gz"
  tar -czf "$OUT" -C "$TMP" . && ok "Xong (gzip): $OUT  ($(du -h "$OUT" | cut -f1))"
fi

cat <<EOF

────────────────────────────────────────────────────────────
 ĐÃ BACKUP: $OUT

 ⚠️  File này đang nằm trên ổ sắp bị xoá. PHẢI copy nó ra
     USB / Google Drive / máy khác TRƯỚC khi cài CachyOS.

 KHÔI PHỤC sau khi cài:
   tar --zstd -xf browser-backup-*.tar.zst -C ~/
   # rồi copy:
   cp -a ~/chromium/.        ~/.config/chromium/
   cp -a ~/keyrings/.        ~/.local/share/keyrings/
   # mở Chromium -> bookmark, mật khẩu, extension, tab cũ quay lại

 LƯU Ý MẬT KHẨU:
   Mật khẩu Chromium mã hoá bằng keyring. Nếu keyring mới
   dùng mật khẩu khác, có thể không mở được. Cách chắc ăn:
   Chromium -> Settings -> Autofill -> Password Manager
            -> Export passwords (CSV)  rồi cất file đó riêng.
────────────────────────────────────────────────────────────
EOF
