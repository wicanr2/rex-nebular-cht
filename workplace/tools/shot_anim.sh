#!/usr/bin/env bash
# 用 ScummVM debugger 的 play_anim 直接播指定動畫檔並截圖 ——
# 驗證第六個文字來源（*.AA 內嵌訊息）的中文化。
#
# 為什麼需要這支：那 199 則訊息散在主線各處（逮捕、搜身、手術檯、片頭太空戰），
# 正常玩要跑很久才看得到；而 intro 和 attract demo 都不含它們
# （intro 是純視覺的太空旅程動畫，130 秒內一個字都沒有 —— 實測過）。
# debugger 的 `play_anim <名稱>`（debugger.cpp:354）可以直接播，是最短路徑。
#
# 用法：shot_anim.sh <輸出目錄> <動畫名> [動畫名...]
#   例：shot_anim.sh /w/out/anim RM001B0 RM301A RM320A
set -euo pipefail

OUT="${1:?用法: shot_anim.sh <輸出目錄> <動畫名>...}"
shift
ANIMS=("$@")
[ ${#ANIMS[@]} -eq 0 ] && { echo "至少給一個動畫名"; exit 2; }

mkdir -p "$OUT"
export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
XVFB_PID=$!
cleanup() { pkill -x scummvm 2>/dev/null || true; kill $XVFB_PID 2>/dev/null || true; }
trap cleanup EXIT
sleep 2

/w/scummvm-src/scummvm --path=/w/game --auto-detect >"$OUT/scummvm.log" 2>&1 &
# [雷] sleep 6 不夠 —— 主選單的選項是逐項淡入的，太早點會落在還沒出現的地方。
# record_gameplay_sync.sh 用的是 10 秒，這裡等到畫面靜止為止，比寫死秒數穩。
sleep 8
for _ in 1 2 3 4 5 6; do
    import -window root /tmp/m1.png; sleep 2
    import -window root /tmp/m2.png
    [ "$(md5sum /tmp/m1.png | cut -c1-8)" = "$(md5sum /tmp/m2.png | cut -c1-8)" ] && break
done
echo "=== 主選單已靜止 ==="

find_wid() {
    local w
    for pat in "Rex Nebular" "ScummVM"; do
        w=$(xdotool search --name "$pat" 2>/dev/null | tail -1 || true)
        if [ -n "$w" ]; then echo "$w"; return 0; fi
    done
    xdotool search --name "." 2>/dev/null | tail -1 || true
}
activate() {
    local wid; wid=$(find_wid)
    if [ -n "$wid" ]; then
        xdotool windowactivate --sync "$wid" 2>/dev/null || true
        xdotool windowfocus "$wid" 2>/dev/null || true
    fi
    return 0
}
click_at() { activate; xdotool mousemove "$1" "$2"; sleep 1; xdotool click --clearmodifiers 1; }
type_line() { activate; xdotool type --delay 40 "$1"; xdotool key Return; }

# 先進遊戲 —— debugger 的 play_anim 需要有場景在跑。
# [雷] 時序照 record_gameplay_sync.sh 實測過的來：點完難度之後還有 **24 秒開場過場**
# （MicroProse 的 Task Force 1942 廣告畫面就在這段裡）。第一版只等 8 秒，
# 於是 play_anim 全打在廣告畫面上，截出來 24 張全是廣告。
click_at 350 375     # Start a new game
sleep 5
click_at 512 372     # 難度
sleep 6
sleep 26             # 開場過場（含廠商廣告）

# [HARD] 「畫面雜湊變了」不能當「已進遊戲」的判準 —— 廣告畫面也一直在變。
# 改用畫面下方那條指令表 UI：它是青藍色系，遊戲裡佔滿整條，其他畫面幾乎沒有。
# 實測區分度：遊戲畫面 0.869；廣告 0.001、intro 0.003、主選單 0.012。
in_game() {
    import -window root /tmp/ig.png
    python3 - <<'PY'
from PIL import Image
im = Image.open("/tmp/ig.png").convert("RGB").crop((192, 490, 832, 585))
n = c = 0
for r, g, b in im.getdata():
    n += 1
    if b > r + 20 and g > r + 10:
        c += 1
print(f"{c/n:.3f}")
PY
}
R=$(in_game)
echo "=== UI 青藍比例 $R ==="
# [雷] 這裡原本寫 `[ "$(echo "$R < 0.5" | bc -l)" = "1" ]` —— 容器裡**沒有 bc**。
# command not found 之後 $(...) 是空字串，跟 "1" 不相等，於是「檢查通過」，
# 腳本一路跑完截了 24 張主選單。判準本身沒跑起來，比沒有判準更糟：
# 它會回報成功。用 awk（一定在）並且把比較結果印出來，看得到才算數。
PASS=$(awk -v r="$R" 'BEGIN { print (r > 0.5) ? "yes" : "no" }')
echo "=== 是否在遊戲中：$PASS ==="
if [ "$PASS" != "yes" ]; then
    echo "### 沒進到遊戲畫面（UI 比例 $R，遊戲中應 > 0.8）—— 還在過場或主選單 ###"
    cp /tmp/ig.png "$OUT/99-not-in-game.png"
    exit 4
fi

for a in "${ANIMS[@]}"; do
    echo "--- $a ---"
    activate
    # [雷] 熱鍵是 Ctrl+**Alt**+D，不是 Ctrl+D。
    # 出處：backends/events/default/default-events.cpp:380
    #   act = new Action("DEBUGGER", ...); act->addDefaultInputMapping("C+A+d");
    # 用錯的話按鍵會被遊戲本身吃掉（滑鼠照動、action line 照更新），
    # 完全看不出 console 沒開 —— 截出來是一堆遊戲畫面而不是動畫。
    xdotool key ctrl+alt+d      # 開 debugger console
    sleep 2
    type_line "play_anim $a"
    sleep 1
    xdotool key Escape          # 關 console，讓動畫在畫面上跑

    # [雷] 不能用「每秒截一張」—— 動畫訊息有起訖幀，短的只顯示一兩秒，
    # 而整段動畫可能幾秒就播完回主選單。第一版每秒截 12 張，12 張全是主選單。
    # 改成錄影再抽格：25fps 全錄下來，一格都不會漏。
    ffmpeg -v error -f x11grab -video_size 1024x768 -framerate 25 -i :99 \
        -t 20 -c:v libx264 -preset ultrafast -pix_fmt yuv420p "$OUT/${a}.mp4" -y
    # 每 0.5 秒抽一格
    mkdir -p "$OUT/$a"
    ffmpeg -v error -i "$OUT/${a}.mp4" -vf fps=2 "$OUT/$a/%03d.png" -y
    echo "  $a：錄 20s，抽 $(ls "$OUT/$a" | wc -l) 格"
done

echo "=== 完成：${#ANIMS[@]} 段動畫 ==="
