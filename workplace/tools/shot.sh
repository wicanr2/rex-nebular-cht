#!/bin/bash
# headless 截圖：跑遊戲 → 依序點擊推進 → 每步截一張。
# 用法：shot.sh <輸出前綴> [點擊序列...]，點擊序列格式 "x,y,等待秒數"
# 例：shot.sh out/10-scaled "350,375,4" "500,430,6"
set -e
export DISPLAY=:99
export HOME=/tmp
export XDG_RUNTIME_DIR=/tmp/runtime
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

PREFIX="${1:-/w/out/shot}"; shift || true

Xvfb :99 -screen 0 1024x768x24 &
XVFB_PID=$!
sleep 2

/w/scummvm-src/scummvm --path=/w/game --auto-detect --no-fullscreen &
GAME_PID=$!
sleep 8

n=0
import -window root "${PREFIX}-$(printf %02d $n).png" || echo "截圖 $n 失敗"

for step in "$@"; do
    if [[ "$step" == t:* ]]; then
        # 打字：t:<文字>,<等待秒數>。用來對 ScummVM 的 debugger console 下指令
        # （例如 "scene 501" 跳場景），這是多場景截圖驗證的關鍵。
        IFS=, read -r txt wait <<< "${step#t:}"
        WID=$(xdotool search --class scummvm | head -1)
        [ -n "$WID" ] && xdotool windowfocus "$WID" 2>/dev/null
        xdotool mousemove 512 400
        xdotool type --delay 80 "$txt"
    elif [[ "$step" == m:* ]]; then
        # 只移動滑鼠不點擊：m:<x>,<y>,<等待秒數>
        # 用來看 hover 才會出現的東西（指令列 status text）
        IFS=, read -r x y wait <<< "${step#m:}"
        xdotool mousemove "$x" "$y"
    elif [[ "$step" == k:* ]]; then
        # 送鍵：k:<keysym>,<等待秒數>
        IFS=, read -r keypart wait <<< "${step#k:}"
        # Xvfb 沒有 window manager，windowactivate 會失敗；
        # 直接對 scummvm 視窗送鍵（找不到就退回送給 root）
        # Xvfb 沒有 window manager，視窗拿不到 input focus，鍵盤事件會掉。
        # windowfocus 走 XSetInputFocus，不需要 WM 也能生效。
        WID=$(xdotool search --class scummvm | head -1)
        [ -n "$WID" ] && xdotool windowfocus "$WID" 2>/dev/null
        xdotool mousemove 512 400
        xdotool key "$keypart"
    else
        IFS=, read -r x y wait <<< "$step"
        xdotool mousemove "$x" "$y"; sleep 1; xdotool click 1
    fi
    sleep "${wait:-4}"
    n=$((n+1))
    import -window root "${PREFIX}-$(printf %02d $n).png" || echo "截圖 $n 失敗"
done

# 收尾：用 -x 比對程序名，不要用 pkill -f（會把執行中的這行 shell 一起殺掉）
kill "$GAME_PID" 2>/dev/null || true
sleep 1
kill -9 "$GAME_PID" 2>/dev/null || true
kill "$XVFB_PID" 2>/dev/null || true
echo "=== 截圖完成 ==="
ls -la "$(dirname "$PREFIX")" | tail -8
