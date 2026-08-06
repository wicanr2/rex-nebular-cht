#!/bin/bash
# 錄原版遊戲音樂當推廣片配樂（rulebook/93 [HARD]：配樂必須用原版真實音訊，不可自產）。
#
# 做法：SDL 的 disk audio driver 把混音結果直接寫檔，不需要音效卡。
# [雷] SDL_DISKAUDIODELAY=0 會讓 mixer 以 CPU 全速跑，55 秒 wall-clock 可以灌出
#      好幾小時的音訊、檔案上看 GB。**一定要設 DELAY=10** 讓它接近即時。
# [雷] 音樂驅動要明確指定，否則 headless 可能選到 null MIDI 只剩稀疏音效。
set -u
export DISPLAY=:99 HOME=/tmp XDG_RUNTIME_DIR=/tmp/rt
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

OUT="${1:-/w/out/audio}"
SECS="${2:-100}"
mkdir -p "$OUT"

export SDL_AUDIODRIVER=disk
export SDL_DISKAUDIOFILE="$OUT/cap.raw"
export SDL_DISKAUDIODELAY=10          # 別設 0

Xvfb :99 -screen 0 1024x768x24 &
XVFB_PID=$!
sleep 2

/w/scummvm-src/scummvm --path=/w/game --auto-detect --no-fullscreen \
    -e adlib --music-volume=255 --output-rate=44100 > /tmp/audio.log 2>&1 &
GAME_PID=$!
sleep 8

# 推進到有音樂的場景：主選單 → 開始新遊戲 → 難度 → 開場
xdotool mousemove 350 375 2>/dev/null; sleep 1; xdotool click 1
sleep 4
xdotool mousemove 512 372 2>/dev/null; sleep 1; xdotool click 1

sleep "$SECS"

kill "$GAME_PID" 2>/dev/null; sleep 1; kill -9 "$GAME_PID" 2>/dev/null
kill "$XVFB_PID" 2>/dev/null
sleep 1

if [ ! -s "$OUT/cap.raw" ]; then
    echo "錄音失敗：cap.raw 不存在或為空"
    exit 1
fi

echo "=== raw 檔 ==="
ls -la "$OUT/cap.raw"

# SDL disk driver 輸出的是 s16le 立體聲 44100Hz
ffmpeg -y -loglevel error -f s16le -ar 44100 -ac 2 -i "$OUT/cap.raw" "$OUT/orig.wav"
echo "=== wav ==="
ffprobe -v error -show_entries format=duration,bit_rate -of default=nw=1 "$OUT/orig.wav"

# [HARD] 驗證非靜音（rulebook/93 鐵則 2：用技術訊號判斷，不靠耳朵猜）
echo "=== 整檔音量 ==="
ffmpeg -v error -i "$OUT/orig.wav" -af volumedetect -f null /dev/null 2>&1 | grep -E 'mean_volume|max_volume'
