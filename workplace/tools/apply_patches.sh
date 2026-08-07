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

# [HARD] 一律走 git apply，不要 fallback 到 patch(1)。
# 解壓出來的樹不是 git repo，git apply 會直接失敗；原本的寫法是退到 `patch -p1`，
# 結果 Linux（GNU patch）套得起來、macOS（BSD patch）靜默套不完整 —— cht.cpp/cht.h
# 這種新增檔進去了，font.cpp 的修改卻沒進去，而 patch 的退出碼是 0。
# 在開發機上完全測不出來，要燒一輪 mac runner 才會看到。
# git init 一下讓 git apply 能用，三平台就走同一條程式碼路徑、同樣的語意。
git init -q .
git apply --check "$PATCH" \
    || { echo "### patch 套不上 ${SCUMMVM_TAG} —— 上游版本可能 drift 了 ###"; exit 3; }
git apply "$PATCH"

# [HARD] 反查：patch 說套上了，就要看得到它應該產生的東西。
for f in engines/mads/cht.cpp engines/mads/cht.h; do
    [ -s "$f" ] || { echo "### $f 不存在 —— patch 沒有真的套上 ###"; exit 4; }
done
# [雷] 這裡原本 grep 的是 'chtEnabled'，但 font.cpp 裡根本沒有那個字串
# （實際是 `cht->enabled()`，font.cpp:179）。條件憑印象寫、沒驗證過，
# 結果這個檢查從第一次執行就在誤報 patch 失敗 —— 而我只看了輸出尾巴和
# 「cht.cpp 存不存在」，沒看退出碼，把 exit 5 當成功，一路帶到 CI 才炸。
# 教訓：驗證條件本身也要驗證一次（拿一份「已知套好」的樹餵進去，確認它說通過）。
grep -q 'ChtSupport' engines/mads/font.cpp \
    || { echo "### font.cpp 沒有中文分支 —— patch 套得不完整 ###"; exit 5; }

# 但單一 grep 仍是抽查，會漏掉沒被 grep 到的那 21 個檔。
# 指紋涵蓋 engines/mads/ 底下每一個 .cpp/.h，任何一處沒套到都會對不上。
EXPECT="${EXPECT_FINGERPRINT:-e6df72ade4f7}"
if command -v python3 >/dev/null; then
    python3 "$HERE/engine_fingerprint.py" "$DEST" --expect "$EXPECT" \
        || { echo "### 引擎指紋不符 —— patch 套得不完整或上游 drift ###"; exit 6; }
else
    # [雷] 這裡原本只印「（無 python3，略過指紋比對）」一行就過去了。
    # rex-mingw image 正好沒裝 python3 —— 於是 **Windows 包的引擎指紋從頭到尾
    # 沒有被驗過一次**，而輸出看起來一切正常。「檢查工具不在」跟「檢查通過」
    # 在輸出上長得幾乎一樣，這是最容易矇混過去的一種。
    # 訊息改成 ### 開頭（跟真正的錯誤同格式），並且明講後果與正確做法。
    echo "### 這個環境沒有 python3，指紋沒有被比對 —— 這不是通過 ###"
    echo "###   後果：patch 套得不完整也看不出來（只 grep 一個字串是抽查）"
    echo "###   做法：先用 rex-cht:dev 套 patch（有 python3），再拿這棵樹去交叉編"
    echo "###          docker run ... rex-cht:dev bash tools/apply_patches.sh <目標>"
    exit 7
fi

echo "=== patch 套用完成：$DEST ==="
