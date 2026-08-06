#!/bin/bash
# 錄真實遊玩片段：畫面走 x11grab，聲音走 SDL disk audio，兩邊同時起跑。
#
# 為什麼要錄真的玩，而不是拿靜態截圖拼：音效是遊戲事件觸發的，錄下來才會落在
# 「該響的那一刻」。後製把音效混到時間軸上是猜的，錄的是真的。
#
# 同步：ScummVM 與 ffmpeg 同時啟動，起點差約 0.5-1 秒（ffmpeg 初始化）。
# 對「背景音樂 + 零星音效」這種素材，這個偏移聽不出來；真要精確就得埋同步標記，
# 不值得為推廣片做到那個程度。
#
# [雷] SDL_DISKAUDIODELAY=0 會讓 mixer 以 CPU 全速跑 → 音訊長度遠超過影片。
#      設 10 讓它接近即時，音畫長度才對得起來。
set -u
export DISPLAY=:99 HOME=/tmp XDG_RUNTIME_DIR=/tmp/rt
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

OUT="${1:-/w/out/gameplay}"
SECS="${2:-75}"
mkdir -p "$OUT"

export SDL_AUDIODRIVER=disk
export SDL_DISKAUDIOFILE="$OUT/cap.raw"
export SDL_DISKAUDIODELAY=10

Xvfb :99 -screen 0 1024x768x24 &
XVFB_PID=$!
sleep 3

# Sound Blaster 兩層都開：FM 音樂 + DAC 數位音效
/w/scummvm-src/scummvm --path=/w/game --auto-detect --no-fullscreen \
    -e adlib --music-volume=192 --sfx-volume=255 --speech-volume=255 \
    --output-rate=44100 > "$OUT/scummvm.log" 2>&1 &
GAME_PID=$!

# 影片：抓整個 root window，之後再裁掉黑邊
ffmpeg -y -loglevel error -f x11grab -framerate 25 -video_size 1024x768 -i :99 \
    -t "$((SECS + 40))" -c:v libx264 -preset ultrafast -qp 0 "$OUT/raw.mkv" &
FF_PID=$!

sleep 10

# [雷] 只做 mousemove + click 不夠 —— 游標會動，但點擊送不到沒有焦點的視窗，
# 於是流程整段停在主選單而畫面看起來一切正常（游標還在正確的選項上）。
# 第一次錄就是這樣，錄了 115 秒全是主選單。先把 ScummVM 視窗啟用起來。
activate() {
    local wid
    wid=$(xdotool search --name "ScummVM" 2>/dev/null | tail -1)
    if [ -n "$wid" ]; then
        xdotool windowactivate --sync "$wid" 2>/dev/null
        xdotool windowfocus "$wid" 2>/dev/null
    fi
}
click_at() {   # $1 x  $2 y
    activate
    xdotool mousemove "$1" "$2" 2>/dev/null
    sleep 1
    xdotool click --clearmodifiers 1 2>/dev/null
}

activate
# [HARD] 驗證流程真的推進了，不要盲送。主選單與遊戲畫面的差異夠大，
# 用畫面雜湊比對就能判斷 —— 沒變就是點擊沒生效，早點知道比錄完 115 秒才發現好。
import -window root /tmp/before.png 2>/dev/null
BEFORE=$(md5sum /tmp/before.png 2>/dev/null | cut -c1-8)

click_at 350 375          # Start a new game
sleep 5
click_at 512 372          # 難度選擇
sleep 6

import -window root /tmp/after.png 2>/dev/null
AFTER=$(md5sum /tmp/after.png 2>/dev/null | cut -c1-8)
if [ "$BEFORE" = "$AFTER" ]; then
    echo "### 點擊後畫面完全沒變（$BEFORE）—— 流程沒推進，還在主選單 ###"
    kill "$GAME_PID" "$FF_PID" "$XVFB_PID" 2>/dev/null
    exit 7
fi
echo "=== 畫面已從 $BEFORE 變成 $AFTER，流程有推進 ==="

sleep 24          # 開場過場（前 30 秒實測是靜音期，音樂在這之後進來）

# 進遊戲後操作：滑過場景讓狀態列出現中文、點物件觸發音效
for i in 1 2 3 4 5 6 7 8; do
    click_at $((280 + i * 55)) $((300 + (i % 4) * 45))
    sleep 6
done

sleep "$SECS"

kill "$GAME_PID" 2>/dev/null; sleep 1; kill -9 "$GAME_PID" 2>/dev/null
wait "$FF_PID" 2>/dev/null
kill "$XVFB_PID" 2>/dev/null
sleep 1

[ -s "$OUT/raw.mkv" ] || { echo "### 影片沒錄到 ###"; exit 1; }
[ -s "$OUT/cap.raw" ] || { echo "### 音訊沒錄到 ###"; exit 1; }

ffmpeg -y -loglevel error -f s16le -ar 44100 -ac 2 -i "$OUT/cap.raw" "$OUT/audio.wav"

echo "=== 影片 ==="
ffprobe -v error -show_entries format=duration -show_entries stream=width,height -of default=nw=1 "$OUT/raw.mkv"
echo "=== 音訊 ==="
ffprobe -v error -show_entries format=duration -of default=nw=1 "$OUT/audio.wav"
echo "=== 音訊逐 15 秒（確認有聲、找音樂進點）==="
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/audio.wav" | cut -d. -f1)
for ((t=0; t<DUR && t<150; t+=15)); do
    M=$(ffmpeg -v info -ss "$t" -t 15 -i "$OUT/audio.wav" -af volumedetect -f null /dev/null 2>&1 | grep max_volume | sed 's/.*max_volume: //')
    printf "  %3ds  max %s\n" "$t" "$M"
done
