#!/bin/bash
# Windows 包的實機驗收：解開 zip、放進遊戲資料、用 wine 真的跑起來截圖。
#
# 為什麼非做不可：check_windows_zip.py 驗的是「包的結構對不對」，
# 但結構全對的包仍可能一開就閃退（缺 DLL、exe 壞掉、路徑寫錯）。
# 驗收要看畫面，不是看檢查腳本全綠。
#
# [HARD] 刻意不把 rex_cht.tsv / rex_big5.fnt 複製進 game/ —— 中文要靠包裡的
#        cht-data/ 經 --extrapath 生效。這樣才驗得到 .bat 裡那條路徑是對的；
#        兩邊都放的話，就算 --extrapath 寫錯也看不出來。
set -u
export DISPLAY=:99 HOME=/tmp WINEPREFIX=/tmp/wp WINEDEBUG=-all XDG_RUNTIME_DIR=/tmp/rt
mkdir -p "$XDG_RUNTIME_DIR" /tmp/wp; chmod 700 "$XDG_RUNTIME_DIR"

ZIP="${1:?用法: verify_windows_zip_wine.sh <zip> <遊戲資料目錄> <輸出目錄>}"
GAMESRC="${2:?}"
OUT="${3:-/w/out/win-verify}"
mkdir -p "$OUT"

RUN=/tmp/wintest
rm -rf "$RUN"; mkdir -p "$RUN"
unzip -q "$ZIP" -d "$RUN"

echo "=== 解開後的檔案 ==="
find "$RUN" -type f | sed "s|$RUN/||" | sort

# 遊戲資料：只複製遊戲本身的檔，不含中文資料
cp "$GAMESRC"/*.hag "$GAMESRC"/*.HAG "$GAMESRC"/*.RES "$GAMESRC"/*.res \
   "$GAMESRC"/asound.* "$GAMESRC"/isound.* "$GAMESRC"/psound.* "$GAMESRC"/rsound.* \
   "$GAMESRC"/xsound.* "$GAMESRC"/digital.aga "$RUN/game/" 2>/dev/null
echo "=== game/ 內中文資料應為 0 個 ==="
ls "$RUN/game/" | grep -c '^rex_' || true

Xvfb :99 -screen 0 1024x768x24 &
XVFB_PID=$!
sleep 3

cd "$RUN"
timeout 120 wine scummvm.exe --config=scummvm.ini --path=game --auto-detect \
    --extrapath=cht-data --no-fullscreen > /tmp/wine-run.log 2>&1 &
GAME_PID=$!
sleep 25

# [HARD] 截主選單之前先大量移動滑鼠製造 dirty。
# 中文標籤畫在文字層，而文字層的 dirty 清除只在畫面有 dirty 時才會清 ——
# 「啟動、等、截圖」的靜止流程下，中文被清掉這件事 100% 測不到。
# 主選單的中文就是這樣在 Linux 靜止截圖下過關、在 wine 下露出英文的。
for i in 1 2 3 4 5 6 7 8; do
    xdotool mousemove $((250 + i * 40)) $((360 + (i % 3) * 30)) 2>/dev/null
    sleep 0.4
done
xdotool mousemove 700 600 2>/dev/null
sleep 2

import -window root "$OUT/win-menu.png" 2>/dev/null || echo "主選單截圖失敗"

# 進遊戲：主選單 → 開始新遊戲 → 難度
xdotool mousemove 350 375 2>/dev/null; sleep 1; xdotool click 1
sleep 5
xdotool mousemove 512 372 2>/dev/null; sleep 1; xdotool click 1
sleep 12
xdotool mousemove 512 350 2>/dev/null; sleep 2

import -window root "$OUT/win-ingame.png" 2>/dev/null || echo "遊戲畫面截圖失敗"

kill "$GAME_PID" 2>/dev/null; sleep 1
pkill -x wine 2>/dev/null      # [雷] 用 -x 不用 -f：pkill -f 會命中 bash 自己那行命令列
kill "$XVFB_PID" 2>/dev/null

echo "=== ScummVM / wine log 摘要 ==="
grep -viE '^[0-9a-f]{4}:|^wine:|fixme|err:|warn:' /tmp/wine-run.log | head -15

echo "=== 截圖 ==="
ls -la "$OUT"
