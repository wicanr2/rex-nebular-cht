#!/bin/bash
# 錄原版 MT-32 配樂（rulebook/93 [HARD]：配樂用原版真實音訊，不自產合成）。
#
# 與 AdLib 版（record_audio.sh）的三個差別：
#  1. -e mt32 走 Munt 模擬（引擎要有 USE_MT32EMU=1，反查 config.mk）
#  2. [HARD] ROM 與 mt32 預設一定要一起設。只給 --music-driver=mt32 而沒有 ROM，
#     ScummVM 開場會彈一次阻擋框再默默退回 AdLib —— 錄出來的是 AdLib，而你以為是 MT-32。
#     ROM 靠 --extrapath 指過去。
#  3. [雷] MT-32 開機要上傳音色，前面那段本來就是靜音。MADS 的音樂進點沒人驗證過，
#     不可直接套用 SCUMM/iMUSE 的結論 —— 錄長一點，事後用 volumedetect 逐段掃出真正進點。
#
# [雷] SDL_DISKAUDIODELAY=0 會讓 mixer 以 CPU 全速跑，幾十秒 wall-clock 灌出好幾小時音訊。
set -u
export DISPLAY=:99 HOME=/tmp XDG_RUNTIME_DIR=/tmp/rt
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

OUT="${1:-/w/out/audio-mt32}"
SECS="${2:-180}"
ROM="${3:-/w/mt32-rom}"
mkdir -p "$OUT"

# --- 前置反查：引擎有沒有真的把 Munt 編進去 ---
if ! grep -q '^USE_MT32EMU = 1' /w/scummvm-src/config.mk; then
    echo "### config.mk 沒有 USE_MT32EMU=1 —— 引擎沒編進 Munt，錄出來一定不是 MT-32 ###"
    exit 2
fi
for f in MT32_CONTROL.ROM MT32_PCM.ROM; do
    [ -s "$ROM/$f" ] || { echo "### 缺 $ROM/$f —— 沒 ROM 會靜默退回 AdLib ###"; exit 3; }
done
echo "=== 前置檢查通過：USE_MT32EMU=1、兩顆 ROM 都在 ==="

export SDL_AUDIODRIVER=disk
export SDL_DISKAUDIOFILE="$OUT/cap.raw"
export SDL_DISKAUDIODELAY=10

Xvfb :99 -screen 0 1024x768x24 &
XVFB_PID=$!
sleep 2

/w/scummvm-src/scummvm --path=/w/game --auto-detect --no-fullscreen \
    -e mt32 --extrapath="$ROM" --music-volume=255 --output-rate=44100 \
    > /tmp/audio-mt32.log 2>&1 &
GAME_PID=$!
sleep 10

# 推進到有音樂的場景：主選單 → 開始新遊戲 → 難度 → 開場
xdotool mousemove 350 375 2>/dev/null; sleep 1; xdotool click 1
sleep 4
xdotool mousemove 512 372 2>/dev/null; sleep 1; xdotool click 1

sleep "$SECS"

kill "$GAME_PID" 2>/dev/null; sleep 1; kill -9 "$GAME_PID" 2>/dev/null
kill "$XVFB_PID" 2>/dev/null
sleep 1

# [HARD] 確認 ScummVM 沒有默默退回 AdLib。Munt 起來時會在 log 留下痕跡；
# 反之若出現找不到 ROM 的訊息，就是退回了。
echo "=== ScummVM log 中的 MT-32 訊息 ==="
grep -iE 'mt-?32|munt|rom|adlib' /tmp/audio-mt32.log | head -20 || echo "（log 沒有相關訊息）"

if [ ! -s "$OUT/cap.raw" ]; then
    echo "錄音失敗：cap.raw 不存在或為空"
    exit 1
fi

ffmpeg -y -loglevel error -f s16le -ar 44100 -ac 2 -i "$OUT/cap.raw" "$OUT/orig.wav"
echo "=== wav ==="
ffprobe -v error -show_entries format=duration,bit_rate -of default=nw=1 "$OUT/orig.wav"

# 整檔音量（rulebook/93 鐵則 2：看技術訊號，不靠耳朵猜）
echo "=== 整檔音量 ==="
ffmpeg -v info -i "$OUT/orig.wav" -af volumedetect -f null /dev/null 2>&1 | grep -E 'mean_volume|max_volume'

# 逐 15 秒掃描找音樂真正進點（MADS 的進點未經驗證，不可套 SCUMM 的結論）
echo "=== 逐段音量（找音樂進點）==="
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT/orig.wav" | cut -d. -f1)
for ((t=0; t<DUR; t+=15)); do
    MEAN=$(ffmpeg -v info -ss "$t" -t 15 -i "$OUT/orig.wav" -af volumedetect -f null /dev/null 2>&1 \
           | grep mean_volume | sed 's/.*mean_volume: //')
    printf "  %4ds - %4ds : %s\n" "$t" "$((t+15))" "$MEAN"
done
