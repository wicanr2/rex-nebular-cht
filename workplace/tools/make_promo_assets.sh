#!/usr/bin/env bash
# 從推廣片衍生兩樣公開素材：分鏡總覽圖（README 用）與靜音 GIF。
#
# 為什麼要靜音 GIF：推廣片的配樂是原版 Sound Blaster 的 AdLib 輸出，那是 MicroProse
# 的著作權素材。公開 repo 只嵌**沒有聲音**的 GIF，完整版連 YouTube（CLAUDE.md §14）。
# GIF 本來就不帶音軌，所以「靜音」不是靠參數關掉，是格式天生如此 —— 但仍然反查一次，
# 免得哪天改成 mp4 預覽卻沿用這支腳本的名字。
#
# 用法：make_promo_assets.sh <推廣片 mp4> <輸出目錄>
set -euo pipefail

MP4="${1:?用法: make_promo_assets.sh <推廣片 mp4> <輸出目錄>}"
OUT="${2:?用法: make_promo_assets.sh <推廣片 mp4> <輸出目錄>}"
[ -s "$MP4" ] || { echo "### 找不到推廣片：$MP4 ###"; exit 2; }
mkdir -p "$OUT"

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$MP4")
case "$DUR" in ''|N/A|0) echo "### 取不到片長 —— 不能當成通過 ###"; exit 3 ;; esac
echo "=== 推廣片 ${DUR}s ==="

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# ---------- 分鏡總覽圖 ----------
# 平均切成 N 段取每段中點。
#
# [HARD] N 必須等於推廣片的分鏡數（`make_promo2.sh` 的 concat 清單長度）。
# 每個分鏡頭尾各有 0.5s 淡入淡出，N 對不上時取樣點會漂到分鏡交界，抽出一張半黑的圖。
# 第一版 N=8 配 9 個分鏡就是這樣：第 3 格落在 16.98s，剛好是引言卡淡出的最後一幀。
# 分鏡數改了，這裡的 COLS×ROWS 要跟著改。
COLS=${COLS:-3}; ROWS=${ROWS:-3}; N=$((COLS * ROWS))
echo "=== 抽 $N 格（${COLS}×${ROWS}）==="
for ((i = 0; i < N; i++)); do
    T=$(awk -v d="$DUR" -v i="$i" -v n="$N" 'BEGIN{printf "%.2f", d*(i+0.5)/n}')
    ffmpeg -v error -y -ss "$T" -i "$MP4" -frames:v 1 "$TMP/f$i.png"
    [ -s "$TMP/f$i.png" ] || { echo "### 第 $i 格（${T}s）抽不到 ###"; exit 4; }
    # 幾乎全黑 = 抽在淡出正中間。這種圖放進總覽等於少一個分鏡，而且不會有人報錯。
    MEAN=$(convert "$TMP/f$i.png" -colorspace Gray -format '%[fx:int(mean*100)]' info:)
    if [ "$MEAN" -lt 3 ]; then
        echo "### 第 $i 格（${T}s）平均亮度 ${MEAN}% —— 抽在淡入淡出中間 ###"
        echo "###   N=$N 對不上分鏡數，調整 COLS/ROWS ###"
        exit 8
    fi
done

montage "$TMP"/f*.png -tile ${COLS}x${ROWS} -geometry 480x270+4+4 \
    -background '#08141a' "$OUT/promo-montage.png"
[ -s "$OUT/promo-montage.png" ] || { echo "### montage 沒產出 ###"; exit 5; }

# ---------- 靜音 GIF ----------
# 取整片中段（頭是標題卡、尾是結尾卡，都是靜態，做成 GIF 沒有動態可看）。
GIF_SS="${GIF_SS:-$(awk -v d="$DUR" 'BEGIN{printf "%.1f", d*0.20}')}"
GIF_T="${GIF_T:-10}"
echo "=== GIF：從 ${GIF_SS}s 取 ${GIF_T}s ==="
ffmpeg -v error -y -ss "$GIF_SS" -t "$GIF_T" -i "$MP4" \
    -vf "fps=12,scale=640:-1:flags=lanczos,palettegen=max_colors=192" "$TMP/pal.png"
ffmpeg -v error -y -ss "$GIF_SS" -t "$GIF_T" -i "$MP4" -i "$TMP/pal.png" \
    -lavfi "fps=12,scale=640:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" \
    -an "$OUT/promo.gif"
[ -s "$OUT/promo.gif" ] || { echo "### GIF 沒產出 ###"; exit 6; }

# [HARD] 反查：GIF 不得帶音軌。ffprobe 數 audio stream，>0 就是出事了。
NA=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$OUT/promo.gif" | grep -c . || true)
[ "$NA" = "0" ] || { echo "### GIF 帶了 $NA 條音軌 —— 版權素材會流出 ###"; exit 7; }

echo "=== 完成 ==="
for f in "$OUT/promo-montage.png" "$OUT/promo.gif"; do
    printf '  %8s KB  %s\n' "$(( $(stat -c%s "$f") / 1024 ))" "$f"
done
