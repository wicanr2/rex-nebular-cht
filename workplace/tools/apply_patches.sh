#!/usr/bin/env bash
# 取得 pristine ScummVM v2.8.0 並套上《錯體奇航》繁中化引擎 patch。
#
# Linux（Windows 交叉編）與 macOS runner 共用這一支，兩邊套的是同一份 patch，
# 引擎指紋才會一致 —— 「只比中文資料 md5」的驗收對「只改引擎」是完全的盲區。
#
# 用法：apply_patches.sh <目標目錄>
set -euo pipefail

DEST="${1:?用法: apply_patches.sh <目標目錄>}"
SCUMMVM_TAG="${SCUMMVM_TAG:-v2.8.0}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="$HERE/../patches/rex-cht-engine.patch"

[ -f "$PATCH" ] || { echo "### 找不到 patch：$PATCH ###"; exit 2; }

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"

TARBALL="$(dirname "$DEST")/scummvm-${SCUMMVM_TAG}.tar.gz"
if [ ! -s "$TARBALL" ]; then
    echo "=== 下載 ScummVM ${SCUMMVM_TAG} ==="
    curl -fsSL -o "$TARBALL" \
      "https://github.com/scummvm/scummvm/archive/refs/tags/${SCUMMVM_TAG}.tar.gz"
fi

mkdir -p "$DEST"
tar xf "$TARBALL" -C "$DEST" --strip-components=1

echo "=== 套用繁中化 patch ==="
cd "$DEST"
# --check 先驗一次：套到一半失敗會留下半套的樹，比乾脆失敗更難查
git apply --check "$PATCH" 2>/dev/null || patch -p1 --dry-run < "$PATCH" >/dev/null \
    || { echo "### patch 套不上 ${SCUMMVM_TAG} —— 上游版本可能 drift 了 ###"; exit 3; }
git apply "$PATCH" 2>/dev/null || patch -p1 < "$PATCH"

# [HARD] 反查：patch 說套上了，就要看得到它應該產生的東西。
# 這兩個檔案是中文路徑的核心，缺任何一個都代表 patch 沒真的生效。
for f in engines/mads/cht.cpp engines/mads/cht.h; do
    [ -s "$f" ] || { echo "### $f 不存在 —— patch 沒有真的套上 ###"; exit 4; }
done
grep -q 'chtEnabled' engines/mads/font.cpp \
    || { echo "### font.cpp 沒有中文分支 —— patch 套得不完整 ###"; exit 5; }

echo "=== patch 套用完成：$DEST ==="
