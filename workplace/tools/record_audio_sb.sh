#!/bin/bash
# 錄原版 Sound Blaster 輸出：AdLib FM 音樂 ＋ DSR 數位音效，兩者都要。
#
# 「Sound Blaster」在這款是兩層，別只錄一層：
#   音樂   SB 卡上的 YM3812 = AdLib 的同一顆 FM 晶片
#          → ScummVM 走 OPL 模擬（engines/mads/sound.cpp:45），資料是 asound.001-009
#   音效   SB 的 DAC
#          → ScummVM 走 audio.cpp:92 playSound() → FAB 解壓 → makeRawStream → mixer
#            資料是 REX009.DSR（封在 HAG 內，不在遊戲根目錄，ls 看不到）
#
# [雷] 先前只設 --music-volume=255 沒設 --sfx-volume，音效被壓在預設音量。
#      兩個都要設，否則錄回來的實質上只有音樂。
# [雷] SDL_DISKAUDIODELAY=0 會讓 mixer 以 CPU 全速跑，灌出好幾小時音訊。
set -u
export DISPLAY=:99 HOME=/tmp XDG_RUNTIME_DIR=/tmp/rt
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

OUT="${1:-/w/out/audio-sb}"
SECS="${2:-150}"
mkdir -p "$OUT"

export SDL_AUDIODRIVER=disk
export SDL_DISKAUDIOFILE="$OUT/cap.raw"
export SDL_DISKAUDIODELAY=10

Xvfb :99 -screen 0 1024x768x24 &
XVFB_PID=$!
sleep 2

/w/scummvm-src/scummvm --path=/w/game --auto-detect --no-fullscreen \
    -e adlib --music-volume=255 --sfx-volume=255 --speech-volume=255 \
    --output-rate=44100 > /tmp/audio-sb.log 2>&1 &
GAME_PID=$!
sleep 8

# 主選單 → 開始新遊戲 → 難度 → 開場
xdotool mousemove 350 375 2>/dev/null; sleep 1; xdotool click 1
sleep 4
xdotool mousemove 512 372 2>/dev/null; sleep 1; xdotool click 1
sleep 30      # 開場過場：音樂進點在這之後

# 觸發音效：在場景裡點物件、走動。開場過完才有得點。
for i in 1 2 3 4 5 6; do
    xdotool mousemove $((300 + i * 60)) $((300 + (i % 3) * 40)) 2>/dev/null
    sleep 1
    xdotool click 1 2>/dev/null
    sleep 6
done

sleep "$SECS"

kill "$GAME_PID" 2>/dev/null; sleep 1; kill -9 "$GAME_PID" 2>/dev/null
kill "$XVFB_PID" 2>/dev/null
sleep 1

# [HARD] DSR 沒載到時 audio.cpp:94 會 warning「DSR file not loaded, not playing sound」。
# 沒有這行才代表數位音效真的有播 —— 不要靠「我設了 sfx-volume」就當它成立。
echo "=== 數位音效載入狀況 ==="
if grep -q "DSR file not loaded" /tmp/audio-sb.log; then
    echo "  ### DSR 沒載入，錄到的只有 FM 音樂 ###"
    grep -c "DSR file not loaded" /tmp/audio-sb.log
else
    echo "  ✓ log 沒有 'DSR file not loaded'"
fi
grep -iE "sound|dsr|invalid sound index" /tmp/audio-sb.log | head -10

[ -s "$OUT/cap.raw" ] || { echo "錄音失敗"; exit 1; }

ffmpeg -y -loglevel error -f s16le -ar 44100 -ac 2 -i "$OUT/cap.raw" "$OUT/orig.wav"
echo "=== wav ==="
ffprobe -v error -show_entries format=duration -of default=nw=1 "$OUT/orig.wav"
echo "=== 整檔音量 ==="
ffmpeg -v info -i "$OUT/orig.wav" -af volumedetect -f null /dev/null 2>&1 | grep -E 'mean_volume|max_volume'
echo "=== 逐 15 秒 ==="
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/orig.wav" | cut -d. -f1)
for ((t=0; t<DUR; t+=15)); do
    MEAN=$(ffmpeg -v info -ss "$t" -t 15 -i "$OUT/orig.wav" -af volumedetect -f null /dev/null 2>&1 \
           | grep mean_volume | sed 's/.*mean_volume: //')
    MAX=$(ffmpeg -v info -ss "$t" -t 15 -i "$OUT/orig.wav" -af volumedetect -f null /dev/null 2>&1 \
           | grep max_volume | sed 's/.*max_volume: //')
    printf "  %4ds-%4ds  mean %-10s max %s\n" "$t" "$((t+15))" "$MEAN" "$MAX"
done
