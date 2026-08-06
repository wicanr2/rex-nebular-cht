#!/bin/bash
set -e
export DISPLAY=:99
export HOME=/tmp
export XDG_RUNTIME_DIR=/tmp/runtime
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
Xvfb :99 -screen 0 1024x768x24 &
XVFB_PID=$!
sleep 2

cd /w
/w/scummvm-src/scummvm --path=/w/game --auto-detect --no-fullscreen &
GAME_PID=$!

sleep 8
echo "=== 視窗清單 ==="
xdotool search --name "" getwindowname %@ 2>&1 || true
WIN=$(xdotool search --onlyvisible --name "." | head -1)
echo "抓到 window id: $WIN"
xdotool windowactivate "$WIN" || true
xdotool windowfocus "$WIN" || true
sleep 1
import -window root /w/out/00-pristine-en.png || echo "screenshot1 failed"

# 直接用滑鼠點「Start a new game」的座標(依 1024x768 root 上的位置換算)
xdotool mousemove --window "$WIN" 350 375
sleep 1
xdotool click --window "$WIN" 1
sleep 4
import -window root /w/out/01-pristine-en-ingame.png || echo "screenshot2 failed"

kill "$GAME_PID" 2>/dev/null || true
sleep 1
kill -9 "$GAME_PID" 2>/dev/null || true
kill "$XVFB_PID" 2>/dev/null || true
echo "=== 截圖完成 ==="
ls -la /w/out/
