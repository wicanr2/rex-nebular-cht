#!/bin/bash
# 多場景截圖驗收：用 --boot-param 逐一跳到指定場景各截一張。
#
# 為什麼一個場景開一次遊戲行程：MADS 的場景狀態彼此有依賴（物品、旗標），
# 同一個行程裡連續跳場景容易帶著上一個場景的殘留狀態，截出來的畫面不可信。
# 一次一個行程比較慢，但每張圖都是乾淨的。
#
# 用法：shot_scenes.sh <輸出目錄> <場景號...>
set -u
export DISPLAY=:99 HOME=/tmp XDG_RUNTIME_DIR=/tmp/rt
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

OUTDIR="${1:-/w/out/scenes}"; shift
mkdir -p "$OUTDIR"

Xvfb :99 -screen 0 1024x768x24 &
XVFB_PID=$!
sleep 2

for scene in "$@"; do
    /w/scummvm-src/scummvm --path=/w/game --auto-detect --no-fullscreen \
        --boot-param="$scene" > "/tmp/scene-$scene.log" 2>&1 &
    GAME_PID=$!
    sleep 8

    # boot_param 是在「開始新遊戲」的流程裡才被讀取的，
    # 所以要先走完 主選單 → 難度選擇，才會落到指定場景
    xdotool mousemove 350 375 2>/dev/null; sleep 1; xdotool click 1
    sleep 4
    xdotool mousemove 512 372 2>/dev/null; sleep 1; xdotool click 1
    sleep 10

    # 移動滑鼠到場景中央：讓指令列（status text）顯示出來，
    # 順便驗證 hotspot 命中區在放大後的座標對不對
    xdotool mousemove 512 350 2>/dev/null
    sleep 2

    import -window root "$OUTDIR/scene-$scene.png" 2>/dev/null \
        || echo "場景 $scene 截圖失敗"

    kill "$GAME_PID" 2>/dev/null
    sleep 1
    kill -9 "$GAME_PID" 2>/dev/null
    sleep 1
done

kill "$XVFB_PID" 2>/dev/null
echo "=== 完成 ==="
ls -la "$OUTDIR" | tail -n +2
