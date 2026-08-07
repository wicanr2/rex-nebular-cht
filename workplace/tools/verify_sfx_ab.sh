#!/bin/bash
# [HARD] 驗證「遊戲執行時 DAC 數位音效真的有播」——用 A/B 對照，不靠設定值自我證明。
#
# 為什麼要這樣驗：
#   - 「我在 ini 設了 sfx_volume=255」不是證據，那只是輸入。
#   - 「log 沒有 DSR file not loaded」是否定證據 —— 根本沒呼叫 playSound 也不會有那行。
#   - 「extract_dsr.py 解得開 22 筆」只證明資料可用，不證明引擎有播。
#
# 正面證據是對照組：同樣的操作序列跑兩次，只差 --sfx-volume（0 vs 255）。
# 有差 = 音效確實有進到 mixer；沒差 = 音效根本沒播，設定是白設的。
#
# 音樂在兩次都開著且相同（--music-volume 固定），所以差異只能來自音效。
set -u
export DISPLAY=:99 HOME=/tmp XDG_RUNTIME_DIR=/tmp/rt
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

OUT="${1:-/w/out/sfx-ab}"
mkdir -p "$OUT"

run_one() {   # $1 sfx 音量  $2 輸出名
    local SFXVOL="$1" NAME="$2"
    pulseaudio --start --exit-idle-time=-1 -n \
        --load="module-null-sink sink_name=rex" \
        --load="module-native-protocol-unix" --log-target=stderr > /dev/null 2>&1
    sleep 3
    pactl set-default-sink rex 2>/dev/null
    pactl list short sinks 2>/dev/null | grep -q rex || { echo "### null sink 失敗 ###"; return 3; }

    Xvfb :99 -screen 0 1024x768x24 & local XV=$!
    sleep 3

    SDL_AUDIODRIVER=pulse PULSE_SINK=rex \
    /w/scummvm-src/scummvm --path=/w/game --auto-detect --no-fullscreen \
        -e adlib --music-volume=192 --sfx-volume="$SFXVOL" --speech-volume="$SFXVOL" \
        --output-rate=44100 > "$OUT/$NAME.log" 2>&1 & local GP=$!

    ffmpeg -y -loglevel error -f pulse -i rex.monitor -t 100 -c:a pcm_s16le "$OUT/$NAME.wav" & local FF=$!

    sleep 10
    local wid
    click() {
        wid=$(xdotool search --name "ScummVM" 2>/dev/null | tail -1)
        [ -n "$wid" ] && { xdotool windowactivate --sync "$wid" 2>/dev/null; xdotool windowfocus "$wid" 2>/dev/null; }
        xdotool mousemove "$1" "$2" 2>/dev/null; sleep 1; xdotool click --clearmodifiers 1 2>/dev/null
    }
    # 兩次跑同一組操作與時間，差異才只來自 sfx 音量
    click 350 375; sleep 5
    click 512 372; sleep 30
    for i in 1 2 3 4 5 6 7 8; do click $((280 + i * 50)) $((300 + (i % 4) * 45)); sleep 5; done
    sleep 10

    kill "$GP" 2>/dev/null; sleep 1; kill -9 "$GP" 2>/dev/null
    wait "$FF" 2>/dev/null
    kill "$XV" 2>/dev/null
    pulseaudio --kill 2>/dev/null
    sleep 2
}

echo "=== A：音效關閉（--sfx-volume=0）——對照組 ==="
run_one 0 sfx-off
echo "=== B：音效開啟（--sfx-volume=255）==="
run_one 255 sfx-on

echo
echo "=== 比對 ==="
for n in sfx-off sfx-on; do
    [ -s "$OUT/$n.wav" ] || { echo "### $n.wav 沒錄到 ###"; exit 1; }
done

for n in sfx-off sfx-on; do
    V=$(ffmpeg -v info -i "$OUT/$n.wav" -af volumedetect -f null /dev/null 2>&1 \
        | grep -E 'mean_volume|max_volume' | sed 's/.*] //' | tr '\n' ' ')
    # DAC 音效是 8000Hz 取樣，內容集中在 4kHz 以下；FM 音樂的能量幾乎全在 1kHz 以下。
    # 取 1-4kHz 這段當指標：音效開啟時這裡應該明顯變大。
    B=$(ffmpeg -v info -i "$OUT/$n.wav" -af "highpass=f=1000,lowpass=f=4000,volumedetect" -f null /dev/null 2>&1 \
        | grep mean_volume | sed 's/.*mean_volume: //')
    printf "  %-8s %s | 1-4kHz %s\n" "$n" "$V" "$B"
done

python3 - "$OUT" <<'PY'
import subprocess, sys, re, os
out = sys.argv[1]
def band(f):
    r = subprocess.run(['ffmpeg','-v','info','-i',f,'-af',
                        'highpass=f=1000,lowpass=f=4000,volumedetect','-f','null','/dev/null'],
                       capture_output=True, text=True)
    m = re.search(r'mean_volume: (-?[\d.]+) dB', r.stderr)
    return float(m.group(1)) if m else None
off, on = band(os.path.join(out,'sfx-off.wav')), band(os.path.join(out,'sfx-on.wav'))
if off is None or on is None:
    sys.exit("### 量不到 1-4kHz 能量，判定失敗 ###")
d = on - off
print(f"\n  1-4kHz 能量差：{d:+.1f} dB（開啟 {on:.1f} / 關閉 {off:.1f}）")
if d > 2:
    print("  ✓ 音效開啟時明顯較大 —— DAC 音效確實有播進 mixer")
else:
    print("  ### 差異不足 2 dB —— 音效可能根本沒播，sfx_volume 是白設的 ###")
    sys.exit(1)
PY
