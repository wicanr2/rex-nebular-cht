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
import -window root /w/out/00-pristine-en.png || echo "screenshot1 failed"

# 用絕對座標(root 座標,對照截圖像素)點「Start a new game」
xdotool mousemove 350 375
sleep 1
xdotool click 1
sleep 4
import -window root /w/out/01-pristine-en-ingame.png || echo "screenshot2 failed"

kill "$GAME_PID" 2>/dev/null || true
sleep 1
kill -9 "$GAME_PID" 2>/dev/null || true
kill "$XVFB_PID" 2>/dev/null || true
echo "=== 截圖完成 ==="
ls -la /w/out/
