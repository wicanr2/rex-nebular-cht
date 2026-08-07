#!/bin/bash
# 決定性實驗：用 ScummVM debugger 的 play_audio 直接叫引擎播一個 DSR 音效，錄下來，
# 再用交叉相關確認錄到的就是那一筆。
#
# 為什麼需要這支：前面幾種驗證都不夠力 ——
#   - ini 設了 sfx_volume 是輸入，不是證據
#   - log 沒有 "DSR file not loaded" 是否定證據（沒呼叫 playSound 也不會有那行）
#   - A/B 對照（sfx 0 vs 255）分不出「音效的貢獻」與「兩次流程推進程度不同」
#   - 一般遊玩錄音裡找不到 DSR 波形，但那可能只是因為那段劇情沒有觸發它 ——
#     playSound 的呼叫點只有 Scene::playSpeech、animation.cpp:578 的動畫 soundId、
#     conversations.cpp:460 的對話語音（走路開門那種音效是 AdLib FM，不走 DSR）
#
# 主動觸發是唯一能把「引擎有沒有能力播」跟「這段劇情有沒有播」分開的方法。
set -u
export DISPLAY=:99 HOME=/tmp XDG_RUNTIME_DIR=/tmp/rt
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

OUT="${1:-/w/out/dsr-verify}"
SFX_INDEX="${2:-16}"      # 預設用最長的那筆（4.98s），好辨識
mkdir -p "$OUT"

pulseaudio --start --exit-idle-time=-1 -n \
    --load="module-null-sink sink_name=rex" \
    --load="module-native-protocol-unix" --log-target=stderr > /dev/null 2>&1
sleep 3
pactl set-default-sink rex 2>/dev/null
pactl list short sinks 2>/dev/null | grep -q rex || { echo "### null sink 失敗 ###"; exit 3; }

Xvfb :99 -screen 0 1024x768x24 & XV=$!
sleep 3

SDL_AUDIODRIVER=pulse PULSE_SINK=rex \
/w/scummvm-src/scummvm --path=/w/game --auto-detect --no-fullscreen \
    -e adlib --music-volume=64 --sfx-volume=255 --speech-volume=255 \
    --output-rate=44100 > "$OUT/scummvm.log" 2>&1 & GP=$!

ffmpeg -y -loglevel error -f pulse -i rex.monitor -t 75 -c:a pcm_s16le "$OUT/rec.wav" & FF=$!

sleep 10
click() {
    local wid; wid=$(xdotool search --name "ScummVM" 2>/dev/null | tail -1)
    [ -n "$wid" ] && { xdotool windowactivate --sync "$wid" 2>/dev/null; xdotool windowfocus "$wid" 2>/dev/null; }
    xdotool mousemove "$1" "$2" 2>/dev/null; sleep 1; xdotool click --clearmodifiers 1 2>/dev/null
}
focus() {
    local wid; wid=$(xdotool search --name "ScummVM" 2>/dev/null | tail -1)
    [ -n "$wid" ] && { xdotool windowactivate --sync "$wid" 2>/dev/null; xdotool windowfocus "$wid" 2>/dev/null; }
}

click 350 375; sleep 5      # Start a new game
click 512 372; sleep 30     # 難度 → 開場過場跑完

import -window root "$OUT/before-debugger.png" 2>/dev/null

# 開 debugger console：ScummVM 的熱鍵是 Ctrl+D
focus
xdotool key --clearmodifiers ctrl+d 2>/dev/null
sleep 3
import -window root "$OUT/debugger.png" 2>/dev/null

# 記一個時間戳：從錄音開始到現在大約多久，之後對照相關峰值位置
echo "=== 送出 play_audio $SFX_INDEX ==="
focus
xdotool type --clearmodifiers --delay 80 "play_audio $SFX_INDEX" 2>/dev/null
sleep 1
xdotool key --clearmodifiers Return 2>/dev/null
sleep 8
import -window root "$OUT/after-cmd.png" 2>/dev/null

# 再播一次，兩次峰值才好跟偶然的背景區分
focus
xdotool type --clearmodifiers --delay 80 "play_audio $SFX_INDEX" 2>/dev/null
sleep 1
xdotool key --clearmodifiers Return 2>/dev/null
sleep 10

kill "$GP" 2>/dev/null; sleep 1; kill -9 "$GP" 2>/dev/null
wait "$FF" 2>/dev/null
kill "$XV" 2>/dev/null
pulseaudio --kill 2>/dev/null

echo "=== ScummVM log 裡的 debugger 痕跡 ==="
grep -iE "sound|dsr|invalid|audio" "$OUT/scummvm.log" | tail -5 || echo "  （無）"

[ -s "$OUT/rec.wav" ] || { echo "### 沒錄到 ###"; exit 1; }
ffmpeg -y -loglevel error -i "$OUT/rec.wav" -ar 8000 -ac 1 "$OUT/rec8k.wav"

echo "=== 交叉相關：錄音裡找不找得到 sfx-$(printf %03d "$SFX_INDEX") ==="
python3 /w/tools/verify_sfx_match.py "$OUT/rec8k.wav" /w/out/sfx 75
