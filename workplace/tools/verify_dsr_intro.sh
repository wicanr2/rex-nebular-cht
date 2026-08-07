#!/bin/bash
# 錄開場動畫，驗證 DSR 數位音效有沒有播。
#
# 為什麼挑開場動畫：playSound 的呼叫點只有三個 ——
#   Scene::playSpeech（語音）、animation.cpp:578（動畫的 soundId）、
#   conversations.cpp:460（對話語音）。
# 一般遊玩（走路、點物件）的音效是 AdLib FM，不走 DSR，所以在駕駛艙晃十分鐘
# 也錄不到 DSR。開場動畫是 MADSEngine 的 animation 路徑，soundId > 0 時就會播。
#
# 主選單第三項「Watch Introduction」直接進動畫，不必先開新遊戲。
set -u
export DISPLAY=:99 HOME=/tmp XDG_RUNTIME_DIR=/tmp/rt
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

OUT="${1:-/w/out/dsr-intro}"
SECS="${2:-110}"
mkdir -p "$OUT"

pulseaudio --start --exit-idle-time=-1 -n \
    --load="module-null-sink sink_name=rex" \
    --load="module-native-protocol-unix" --log-target=stderr > /dev/null 2>&1
sleep 3
pactl set-default-sink rex 2>/dev/null
pactl list short sinks 2>/dev/null | grep -q rex || { echo "### null sink 失敗 ###"; exit 3; }

Xvfb :99 -screen 0 1024x768x24 & XV=$!
sleep 3

# 音樂壓低、音效拉滿：兩者混在一起時，DSR 的波形才不會被 FM 蓋掉，
# 交叉相關才容易對上。這是為了量測，不是給玩家的設定。
SDL_AUDIODRIVER=pulse PULSE_SINK=rex \
/w/scummvm-src/scummvm --path=/w/game --auto-detect --no-fullscreen \
    -e adlib --music-volume=32 --sfx-volume=255 --speech-volume=255 \
    --output-rate=44100 > "$OUT/scummvm.log" 2>&1 & GP=$!

ffmpeg -y -loglevel error -f pulse -i rex.monitor -t "$SECS" -c:a pcm_s16le "$OUT/rec.wav" & FF=$!

sleep 10
wid=$(xdotool search --name "ScummVM" 2>/dev/null | tail -1)
[ -n "$wid" ] && { xdotool windowactivate --sync "$wid" 2>/dev/null; xdotool windowfocus "$wid" 2>/dev/null; }
import -window root "$OUT/menu.png" 2>/dev/null
B=$(md5sum "$OUT/menu.png" | cut -c1-8)

# 主選單第三項：Watch Introduction（y 約 455）
xdotool mousemove 350 455 2>/dev/null; sleep 1; xdotool click --clearmodifiers 1 2>/dev/null
sleep 12

import -window root "$OUT/intro.png" 2>/dev/null
A=$(md5sum "$OUT/intro.png" | cut -c1-8)
if [ "$B" = "$A" ]; then
    echo "### 畫面沒變（$B）—— 沒進到開場動畫 ###"
    kill "$GP" "$FF" "$XV" 2>/dev/null; pulseaudio --kill 2>/dev/null; exit 7
fi
echo "=== 畫面 $B → $A，已進開場動畫 ==="

sleep $((SECS - 30))
import -window root "$OUT/intro-late.png" 2>/dev/null

kill "$GP" 2>/dev/null; sleep 1; kill -9 "$GP" 2>/dev/null
wait "$FF" 2>/dev/null
kill "$XV" 2>/dev/null
pulseaudio --kill 2>/dev/null

[ -s "$OUT/rec.wav" ] || { echo "### 沒錄到 ###"; exit 1; }
ffmpeg -y -loglevel error -i "$OUT/rec.wav" -ar 8000 -ac 1 "$OUT/rec8k.wav"

echo "=== 整體音量 ==="
ffmpeg -v info -i "$OUT/rec.wav" -af volumedetect -f null /dev/null 2>&1 | grep -E 'mean_volume|max_volume'

echo "=== 交叉相關：開場動畫裡有沒有 DSR 音效 ==="
python3 /w/tools/verify_sfx_match.py "$OUT/rec8k.wav" /w/out/sfx "$SECS"
