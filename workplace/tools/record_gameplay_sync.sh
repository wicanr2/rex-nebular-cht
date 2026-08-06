#!/bin/bash
# 錄真實遊玩：畫面 x11grab，聲音 PulseAudio null sink，**音畫同步**。
#
# 為什麼不用 SDL disk audio（tools/record_gameplay.sh 的做法）：
# 它是「盡快把 mixer 輸出寫檔」，不受真實時間約束——實測 110 秒的遊玩錄出
# 397 秒的音訊。拿去跟畫面合成，音畫差 3.6 倍，「音效落在該響的那一刻」不成立。
# PulseAudio 的 null sink 沒有實體硬體，但**按真實時間消耗取樣**（模擬音效卡時鐘），
# ScummVM 就會以正常速度產生音訊。
#
# [雷] x11grab 跑起來之後 xdotool 的 click 送不進 ScummVM 視窗，游標卻照常會動 ——
#      流程整段停在主選單而畫面看起來一切正常。每次點擊前要 windowactivate。
set -u
export DISPLAY=:99 HOME=/tmp XDG_RUNTIME_DIR=/tmp/rt
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

OUT="${1:-/w/out/gameplay-sync}"
SECS="${2:-95}"
mkdir -p "$OUT"

# --- PulseAudio：null sink，無硬體但有時鐘 ---
pulseaudio --start --exit-idle-time=-1 --disallow-exit -n \
    --load="module-null-sink sink_name=rex sink_properties=device.description=rex" \
    --load="module-native-protocol-unix" --log-target=stderr > "$OUT/pulse.log" 2>&1
sleep 3
pactl set-default-sink rex 2>/dev/null
if ! pactl list short sinks 2>/dev/null | grep -q rex; then
    echo "### null sink 沒建起來，錄不到聲音 ###"; cat "$OUT/pulse.log" | tail -5; exit 3
fi
echo "=== PulseAudio null sink 就緒 ==="
pactl list short sinks

Xvfb :99 -screen 0 1024x768x24 &
XVFB_PID=$!
sleep 3

# SB 兩層都開：FM 音樂 + DAC 數位音效
SDL_AUDIODRIVER=pulse PULSE_SINK=rex \
/w/scummvm-src/scummvm --path=/w/game --auto-detect --no-fullscreen \
    -e adlib --music-volume=192 --sfx-volume=255 --speech-volume=255 \
    --output-rate=44100 > "$OUT/scummvm.log" 2>&1 &
GAME_PID=$!

TOTAL=$((SECS + 45))
# 畫面與聲音由同一個 ffmpeg 行程錄，時間軸天生對齊
ffmpeg -y -loglevel error \
    -f x11grab -framerate 25 -video_size 1024x768 -i :99 \
    -f pulse -i rex.monitor \
    -t "$TOTAL" -c:v libx264 -preset ultrafast -qp 0 -c:a pcm_s16le \
    "$OUT/raw.mkv" &
FF_PID=$!

sleep 10

activate() {
    local wid
    wid=$(xdotool search --name "ScummVM" 2>/dev/null | tail -1)
    [ -n "$wid" ] && { xdotool windowactivate --sync "$wid" 2>/dev/null; xdotool windowfocus "$wid" 2>/dev/null; }
}
click_at() { activate; xdotool mousemove "$1" "$2" 2>/dev/null; sleep 1; xdotool click --clearmodifiers 1 2>/dev/null; }

activate
import -window root /tmp/before.png 2>/dev/null
BEFORE=$(md5sum /tmp/before.png 2>/dev/null | cut -c1-8)

click_at 350 375          # Start a new game
sleep 5
click_at 512 372          # 難度
sleep 6

import -window root /tmp/after.png 2>/dev/null
AFTER=$(md5sum /tmp/after.png 2>/dev/null | cut -c1-8)
if [ "$BEFORE" = "$AFTER" ]; then
    echo "### 點擊後畫面沒變（$BEFORE）—— 還停在主選單 ###"
    kill "$GAME_PID" "$FF_PID" "$XVFB_PID" 2>/dev/null; exit 7
fi
echo "=== 畫面 $BEFORE → $AFTER，流程有推進 ==="

sleep 24          # 開場過場（前 30 秒是靜音期）

# 進場後操作：滑過場景讓狀態列出現中文、點物件觸發 DAC 音效
for i in 1 2 3 4 5 6 7 8 9 10; do
    click_at $((280 + i * 50)) $((300 + (i % 4) * 45))
    sleep 6
done

sleep "$SECS"

kill "$GAME_PID" 2>/dev/null; sleep 1; kill -9 "$GAME_PID" 2>/dev/null
wait "$FF_PID" 2>/dev/null
kill "$XVFB_PID" 2>/dev/null
pulseaudio --kill 2>/dev/null
sleep 1

[ -s "$OUT/raw.mkv" ] || { echo "### 沒錄到 ###"; exit 1; }

echo "=== [HARD] 音畫必須等長，差很多就是沒同步 ==="
# [雷] 不能用 stream=duration —— 邊錄邊被 kill 的 mkv，stream 層沒有 duration，
# ffprobe 回 "N/A"。而 awk 拿兩個 N/A 相減會算出 0，於是印出「✓ 差 0s，同步」——
# 檢查在拿不到資料時靜默通過，比沒有檢查更糟。實測踩過一次。
# format=duration 對同一個檔是有值的；音訊長度用解碼實測。
# [雷2] 也不能拿「容器長度 vs 音訊長度」比 —— 容器 duration 取的是最長那一軌，
# 所以影片 110s 配音訊 397s 的檔，容器就是 397s，兩者永遠「一致」。
# 要比的是 video 軌 vs audio 軌，而且兩邊都要解碼實測。
track_len() {   # $1 檔案  $2 v|a
    ffmpeg -v info -i "$1" -map "0:$2" -f null - 2>&1 \
      | grep -oE 'time=[0-9][0-9:.]+' | tail -1 | cut -d= -f2 \
      | awk -F: '{print ($1*3600)+($2*60)+$3}'
}
VD=$(track_len "$OUT/raw.mkv" v)
AD=$(track_len "$OUT/raw.mkv" a)
for pair in "影片:$VD" "音訊:$AD"; do
    case "${pair##*:}" in
        ''|0|0.0) echo "### 取不到${pair%%:*}長度 —— 不能當成通過 ###"; exit 8 ;;
    esac
done
echo "  影片 ${VD}s / 音訊 ${AD}s"
awk -v v="$VD" -v a="$AD" 'BEGIN{d=(v>a?v-a:a-v); if (d>3){print "  ### 差 "d"s，沒同步 ###"; exit 1} else print "  ✓ 差 "d"s，同步"}' || exit 8
DUR_F="$VD"

echo "=== 音訊逐 15 秒 ==="
DUR=${DUR_F%.*}
for ((t=0; t<DUR; t+=15)); do
    M=$(ffmpeg -v info -ss "$t" -t 15 -i "$OUT/raw.mkv" -map 0:a -af volumedetect -f null /dev/null 2>&1 | grep max_volume | sed 's/.*max_volume: //')
    printf "  %3ds  max %s\n" "$t" "$M"
done
