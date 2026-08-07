#!/usr/bin/env bash
# Linux 交付：AppImage（本機測試用，含遊戲本體）＋ patch zip（公開散布用，只有中文資料）。
#
# 這支之前是一連串手動步驟，沒留成腳本 —— 於是引擎一改就得憑記憶重做一次，
# 而「AppDir 裡的 scummvm 忘了換」這種錯不會有任何徵兆（包裝得起來、跑得動、
# 只是裝的是舊引擎）。Gobliiins 就踩過：六個包全 ✓，其中兩個是修正前的引擎。
#
# 用法：package_linux.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$HERE/.."
ROOT="$W/.."
STAGE="$HERE/pkg/build/appimage-patch-staging"
APPDIR="$STAGE/appimage/AppDir"
PATCHDIR="$STAGE/patch"
CACHE="$HERE/pkg/cache"
# [雷] 產物一律進 workplace/dist-all/（既有慣例，其他平台的腳本都寫這裡）。
# 第一版寫成 $ROOT/dist-all 也就是 repo 根，結果同時存在兩個 dist-all：
# 一個裝新的 Linux 包、一個裝舊的 Windows/macOS 包，而兩邊看起來都很正常。
# 「每平台留最新一份」的前提是只有一個目錄。
DIST="$W/dist-all"

BIN="$W/scummvm-src/scummvm"
[ -x "$BIN" ] || { echo "### 找不到自編的 scummvm，先跑 tools/build.sh ###"; exit 2; }
[ -d "$APPDIR" ] || { echo "### 找不到 AppDir staging：$APPDIR ###"; exit 2; }
mkdir -p "$DIST"

FP=$(python3 "$HERE/engine_fingerprint.py" "$W/scummvm-src" | grep -o '[0-9a-f]\{12\}')
echo "=== 引擎指紋 $FP ==="

# ---- 1. 更新 staging ----
cp "$BIN" "$APPDIR/usr/bin/scummvm"
for d in "$APPDIR/usr/share/rexnebular-game" "$APPDIR/cht-data" "$PATCHDIR/cht-data"; do
    [ -d "$d" ] || continue
    cp "$ROOT/cht-data/rex_cht.tsv"  "$d/"
    cp "$ROOT/cht-data/rex_big5.fnt" "$d/"
done
for d in "$APPDIR/cht-data" "$PATCHDIR/cht-data"; do
    [ -d "$d" ] && cp "$ROOT/cht-data/ENGINE.txt" "$d/"
done

# [HARD] 反查：cp 完要確認包裡的東西真的換了。比 binary 的 md5 與資料的 md5，
# 兩邊都要 —— 只比資料的驗收，對「只改引擎」是完全的盲區。
a=$(md5sum "$BIN" | cut -d' ' -f1)
b=$(md5sum "$APPDIR/usr/bin/scummvm" | cut -d' ' -f1)
[ "$a" = "$b" ] || { echo "### AppDir 的 scummvm 沒換到 ###"; exit 3; }
c=$(md5sum "$ROOT/cht-data/rex_cht.tsv" | cut -d' ' -f1)
d2=$(md5sum "$APPDIR/usr/share/rexnebular-game/rex_cht.tsv" | cut -d' ' -f1)
[ "$c" = "$d2" ] || { echo "### AppDir 的中文資料沒換到 ###"; exit 3; }
grep -q "$FP" "$PATCHDIR/cht-data/ENGINE.txt" || { echo "### ENGINE.txt 的指紋不是 $FP ###"; exit 3; }
echo "  ✓ binary ${a:0:12} / 資料 ${c:0:12} / 指紋 $FP 都已更新"

# ---- 2. AppImage ----
export ARCH=x86_64
"$CACHE/appimagetool-x86_64.AppImage" --appimage-extract-and-run \
    --runtime-file "$CACHE/runtime-x86_64" \
    "$APPDIR" "$DIST/RexNebular-CHT-x86_64.AppImage" >/dev/null 2>&1
chmod +x "$DIST/RexNebular-CHT-x86_64.AppImage"
echo "  ✓ AppImage $(du -h "$DIST/RexNebular-CHT-x86_64.AppImage" | cut -f1)"

# ---- 3. patch zip（公開散布：只有中文資料，不含遊戲本體）----
rm -f "$DIST/rexnebular-cht-patch.zip"
( cd "$PATCHDIR" && zip -qr "$DIST/rexnebular-cht-patch.zip" . )
echo "  ✓ patch zip $(du -h "$DIST/rexnebular-cht-patch.zip" | cut -f1)"

# [HARD] patch zip 絕不能含遊戲本體。這裡是公開散布的那一包。
if unzip -l "$DIST/rexnebular-cht-patch.zip" | grep -qiE '\.hag|\.res|section[0-9]|asound|psound|rsound'; then
    echo "### patch zip 裡有遊戲資料檔 ###"
    unzip -l "$DIST/rexnebular-cht-patch.zip" | grep -iE '\.hag|\.res|section[0-9]|sound'
    exit 4
fi
echo "  ✓ patch zip 不含遊戲資料"

echo "=== Linux 打包完成 ==="
ls -la "$DIST/RexNebular-CHT-x86_64.AppImage" "$DIST/rexnebular-cht-patch.zip"
