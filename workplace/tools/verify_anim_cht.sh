#!/usr/bin/env bash
# 驗證第六個文字來源（*.AA 動畫內嵌訊息）的替換真的有發生。
#
# 為什麼不用截圖驗：那 199 則散在開場、結局、死亡動畫與各場景過場裡，
# 有些只顯示一兩秒。試過三條路都不通 ——
#   1. 「Watch introduction」錄 130 秒，一則都沒照到（開場那段字幕出現的幀很短）
#   2. attract demo：這款主選單放著 200 秒完全不動，沒有 demo
#   3. debugger `play_anim`：它吃的是 .RES 播放清單不是 .AA，而且播完立刻回主選單
# 改用引擎自己的 debug 輸出當證據：命中就印 key，沒命中連同原文一起印。
# 這是「替換有沒有發生」的直接因果，比截到某一幀更完整 —— 它一次涵蓋整段動畫的每一則。
#
# 用法：verify_anim_cht.sh <輸出目錄>
set -euo pipefail

OUT="${1:?用法: verify_anim_cht.sh <輸出目錄>}"
mkdir -p "$OUT"
export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
XVFB_PID=$!
cleanup() { pkill -x scummvm 2>/dev/null || true; kill $XVFB_PID 2>/dev/null || true; }
trap cleanup EXIT
sleep 2

# --debuglevel 打開 [CHT] 那幾行。開場動畫（rexopen.res）會依序載入 31 段 .AA，
# 但**前 8 段一則訊息都沒有**（RM942AA/RM944A/RM901A/B/RM902A/RM903A/RM904C/RM950A），
# 第一個帶訊息的是第 9 段 RM951A。所以等太短會看到「命中 0、未命中 0」，
# 那不是替換壞掉，是根本還沒播到有字的段落 —— 第一版只等 60 秒就是這樣。
/w/scummvm-src/scummvm --path=/w/game --auto-detect --debuglevel=3 >"$OUT/run.log" 2>&1 &
sleep 8

find_wid() {
    local w
    for pat in "Rex Nebular" "ScummVM"; do
        w=$(xdotool search --name "$pat" 2>/dev/null | tail -1 || true)
        if [ -n "$w" ]; then echo "$w"; return 0; fi
    done
    xdotool search --name "." 2>/dev/null | tail -1 || true
}
activate() {
    local wid; wid=$(find_wid)
    if [ -n "$wid" ]; then
        xdotool windowactivate --sync "$wid" 2>/dev/null || true
        xdotool windowfocus "$wid" 2>/dev/null || true
    fi
    return 0
}
click_at() { activate; xdotool mousemove "$1" "$2"; sleep 1; xdotool click --clearmodifiers 1; }

# 等主選單靜止（選項是逐項淡入的）
for _ in 1 2 3 4 5 6; do
    import -window root /tmp/v1.png; sleep 2
    import -window root /tmp/v2.png
    [ "$(md5sum /tmp/v1.png | cut -c1-8)" = "$(md5sum /tmp/v2.png | cut -c1-8)" ] && break
done

import -window root "$OUT/00-menu.png"
MENU=$(md5sum "$OUT/00-menu.png" | cut -c1-8)

click_at 350 455      # Watch introduction → 載入 rexopen.res 的 31 段動畫
sleep 4
import -window root "$OUT/01-after.png"
AFTER=$(md5sum "$OUT/01-after.png" | cut -c1-8)
echo "=== 畫面 $MENU → $AFTER ==="
if [ "$MENU" = "$AFTER" ]; then
    echo "### 點了「Watch introduction」畫面沒變 —— 點擊沒生效，後面驗什麼都沒意義 ###"
    exit 6
fi
sleep 175

pkill -x scummvm 2>/dev/null || true
sleep 2

# [HARD] 先確認引擎讀到的是**新**資料。中文資料有兩份（cht-data/ 與 game/），
# 沒同步的話這支腳本會很認真地驗一份舊表，而且不會有任何徵兆。
EXPECT_ROWS=$(grep -avc '^#' /w/game/rex_cht.tsv)
GOT=$(grep -o "替換表 [0-9]* 筆" "$OUT/run.log" | head -1 | grep -o "[0-9]*" || echo 0)
echo "=== 引擎讀到替換表 $GOT 筆（game/ 目錄是 $EXPECT_ROWS 筆）==="
if [ "$GOT" != "$EXPECT_ROWS" ]; then
    echo "### 引擎讀到的替換表跟 game/ 對不上 —— 先跑 tools/sync_cht_data.sh ###"
    exit 5
fi

HIT=$(grep -c "已替換" "$OUT/run.log" || true)
MISS=$(grep -c "查無譯文" "$OUT/run.log" || true)
echo "=== 動畫內嵌訊息替換結果 ==="
echo "  命中 $HIT 則 / 未命中 $MISS 則"

if [ "$MISS" -gt 0 ]; then
    echo "--- 未命中的（key 組法對不上抽字工具）---"
    grep "查無譯文" "$OUT/run.log" | head -20
fi

# [HARD] 正對照：命中數為 0 有兩種可能 —— 替換全掛，或這段流程根本沒載入任何動畫。
# 要能分辨，就得確認「引擎確實走過這段程式碼」：命中 + 未命中都是 0 表示
# 一則都沒載入，那是流程問題不是替換問題，不可以report成通過。
TOTAL=$((HIT + MISS))
if [ "$TOTAL" -eq 0 ]; then
    echo "### 這段流程一則動畫訊息都沒載入 —— 驗不到東西，不算通過 ###"
    exit 3
fi
if [ "$MISS" -gt 0 ]; then
    echo "### 有 $MISS 則沒命中替換表 ###"
    exit 4
fi
echo "  ✓ 載入 $TOTAL 則，全部命中替換表"
