#!/usr/bin/env bash
# 《錯體奇航》繁中化推廣片。全 docker、無剪輯軟體。
#
# [HARD] 不用 zoompan —— 它的 d 是「每個輸入幀輸出 d 幀」，配上前置 fps 會變成
#        (FPS*S)² 幀，6 秒 25fps ≈ 22500 幀，CPU 燒好幾分鐘。靜態圖 + fade 就夠看。
# [HARD] 音樂與音效都用原版實錄／原版資料，不自產合成音：
#        音樂 tools/record_audio_sb.sh（AdLib FM = SB 卡上的 YM3812）
#        音效 tools/extract_dsr.py（REX009.DSR，SB 的 DAC 那一層）
set -eu

# ===== theme：從遊戲截圖萃取，不沿用其他專案 =====
# 取色來源：駕駛艙 #244148 / #3B7887，海邊 #4E5E68 / #6166A2，台詞的亮青
THEME_NAME="太空艙青"
BG_DEEP='#08141a'; BG_LITE='#244148'
ACCENT='#4ec9d9'          # 遊戲台詞的亮青
ACCENT_DIM='#2a7c88'
TEXT='#d1dae3'; DIM='#7f95a3'
FB=/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc      # 科幻 → 無襯線
FR=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
W=1280; H=720; FPS=25
SHOT=/w/out; OUT=/w/out/promo; TMP=/tmp/promo
mkdir -p "$OUT" "$TMP"

# ---------- 版面函式（skill 要求 5-6 種輪流用，避免整片千篇一律）----------

# 標題卡：徑向漸層 + 三層浮雕標題
card() { # $1 out  $2 中標  $3 英標  $4 副標
  convert -size ${W}x${H} "radial-gradient:${BG_LITE}-${BG_DEEP}" \
    -font "$FB" -gravity center \
    -fill "$ACCENT_DIM" -pointsize 96 -annotate +3+3 "$2" \
    -fill "$ACCENT"     -pointsize 96 -annotate +0+0 "$2" \
    -font "$FR" -fill "$TEXT" -pointsize 34 -annotate +0+92 "$3" \
    -fill "$DIM" -pointsize 26 -annotate +0+160 "$4" "$1"
}

# 滿版截圖 + 下三分之一字幕條
slide_full() { # $1 out  $2 截圖  $3 字幕
  convert "$2" -crop 640x400+192+180 +repage -resize ${W}x${H}^ -gravity center -extent ${W}x${H} "$TMP/f.png"
  convert "$TMP/f.png" -fill "#000000bb" -draw "rectangle 0,$((H-110)) ${W},${H}" \
    -font "$FR" -fill "$TEXT" -gravity south -pointsize 36 -annotate +0+38 "$3" "$1"
}

# 框內截圖：青框置中，上方留標題
slide_frame() { # $1 out  $2 截圖  $3 標題  $4 字幕
  convert -size ${W}x${H} "gradient:${BG_LITE}-${BG_DEEP}" "$TMP/bg.png"
  convert "$2" -crop 640x400+192+180 +repage -resize x460 -bordercolor "$ACCENT_DIM" -border 3 "$TMP/sc.png"
  convert "$TMP/bg.png" \( "$TMP/sc.png" \) -gravity north -geometry +0+118 -composite \
    -font "$FB" -fill "$ACCENT" -gravity north -pointsize 40 -annotate +0+44 "$3" \
    -font "$FR" -fill "$TEXT" -gravity south -pointsize 32 -annotate +0+34 "$4" "$1"
}

# 對白卡：巨型引號 + 左對齊譯文 + 英文原文小字（秀翻譯又有層次）
dcard() { # $1 out  $2 中文譯文  $3 英文原文
  convert -size ${W}x${H} "gradient:${BG_DEEP}-${BG_LITE}" \
    -font "$FB" -fill "${ACCENT_DIM}" -pointsize 300 -gravity northwest -annotate +40-60 '"' \
    -font "$FR" -fill "$TEXT" -pointsize 44 -gravity west -annotate +110+0 "$2" \
    -font "$FR" -fill "$DIM"  -pointsize 24 -gravity southwest -annotate +112+90 "$3" "$1"
}

# 中英前後對比：左英文原版 / 右繁中版，中間箭頭。中文化專案最有說服力的一張。
split_ba() { # $1 out  $2 英文截圖  $3 中文截圖  $4 標題
  convert -size ${W}x${H} "gradient:${BG_DEEP}-${BG_LITE}" "$TMP/sb.png"
  convert "$2" -crop 640x400+192+180 +repage -resize 560x350! -bordercolor "$DIM"    -border 2 "$TMP/l.png"
  convert "$3" -crop 640x400+192+180 +repage -resize 560x350! -bordercolor "$ACCENT" -border 2 "$TMP/r.png"
  convert "$TMP/sb.png" \
    \( "$TMP/l.png" \) -gravity west  -geometry +30+30 -composite \
    \( "$TMP/r.png" \) -gravity east  -geometry +30+30 -composite \
    -font "$FB" -fill "$ACCENT" -gravity north -pointsize 40 -annotate +0+40 "$4" \
    -font "$FR" -fill "$DIM"  -gravity west -pointsize 26 -annotate +150+230 "英文原版" \
    -font "$FR" -fill "$TEXT" -gravity east -pointsize 26 -annotate +150+230 "繁體中文化" \
    -font "$FB" -fill "$ACCENT" -gravity center -pointsize 64 -annotate +0+30 "→" "$1"
}

# 數據卡：把「翻了多少」講清楚
statcard() { # $1 out  $2 標題  $3 大數字  $4 說明
  convert -size ${W}x${H} "radial-gradient:${BG_LITE}-${BG_DEEP}" \
    -font "$FR" -fill "$DIM" -gravity center -pointsize 30 -annotate +0-130 "$2" \
    -font "$FB" -fill "$ACCENT" -gravity center -pointsize 150 -annotate +0-20 "$3" \
    -font "$FR" -fill "$TEXT" -gravity center -pointsize 30 -annotate +0+100 "$4" "$1"
}

# 靜態 + 淡入淡出（不用 zoompan，見檔頭）
clip() { # $1 png  $2 mp4  $3 秒
  local FO; FO=$(awk "BEGIN{print $3-0.5}")
  ffmpeg -y -loglevel error -loop 1 -i "$1" -t "$3" -r $FPS \
    -vf "fade=t=in:st=0:d=0.5,fade=t=out:st=$FO:d=0.5,format=yuv420p" \
    -threads 2 -c:v libx264 -preset veryfast -pix_fmt yuv420p "$2"
}

# ===== 分鏡：骨架 C（對白精選輯）——這款賣點就是笑點 =====
card       "$TMP/00.png" '錯體奇航' 'Rex Nebular and the Cosmic Gender Bender' 'MicroProse 1992 ・ 繁體中文化'
slide_full "$TMP/01.png" "$SHOT/clean-cht.png" '太空打撈員雷克斯・尼布勒，任務是取回一只花瓶'
dcard      "$TMP/02.png" '夢到自己被人打下來……然後一頭撞進……糟了！' 'I dreamed I was shot down . . . and crashed into the . . . Uh oh!'
slide_frame "$TMP/03.png" "$SHOT/scenes/scene-701.png" '一顆只剩女人的星球' '船沉了，而這裡的居民對「男人」有點意見'
dcard      "$TMP/04.png" '好棒棒喔，真的有夠棒。現在你連沒生命的東西都要交談。' 'Great. Just great. Now you are trying to talk to inanimate objects.'
slide_frame "$TMP/05.png" "$SHOT/scenes/scene-301.png" '沉沒的城市' '指令表、物品欄、旁白，全部翻成繁體中文'
split_ba   "$TMP/06.png" "$SHOT/clean-en.png" "$SHOT/clean-cht.png" '指令表 ・ 物品欄 ・ 對白 全中文'
statcard   "$TMP/07.png" '這一路上的每一句話' '4357' '則對白與詞條 ・ 2394 字自製點陣字型'
card       "$TMP/99.png" '錯體奇航' 'Rex Nebular and the Cosmic Gender Bender' '繁體中文化 ・ 倚天點陣字 ・ patch-only'

# ===== 合成 =====
LIST="$TMP/list.txt"; : > "$LIST"
for f in 00 01 02 03 04 05 06 07 99; do
  case "$f" in
    00|99) SEC=6 ;;      # 頭尾留長
    02|04|06) SEC=5 ;;   # 對白卡（喜劇快切）
    *) SEC=5 ;;
  esac
  clip "$TMP/$f.png" "$TMP/c_$f.mp4" $SEC
  echo "file '$TMP/c_$f.mp4'" >> "$LIST"
done

ffmpeg -y -loglevel error -f concat -safe 0 -i "$LIST" \
  -threads 2 -c:v libx264 -preset veryfast -pix_fmt yuv420p "$TMP/silent.mp4"

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TMP/silent.mp4")
FO=$(awk "BEGIN{print $DUR-3}")

# ===== 音訊：Sound Blaster 的兩層都要 =====
# 音樂 = SB 卡上的 YM3812 FM 合成（跟 AdLib 同一顆晶片），SDL disk audio 實錄
# 音效 = SB 的 DAC，從 REX009.DSR 抽出的原版 8-bit PCM（tools/extract_dsr.py）
# 兩者都是原版真實素材，沒有一個位元是合成的。
BGM=/w/out/audio-sb/bgm.wav
[ -s "$BGM" ] || BGM=/w/out/audio/bgm.wav
SFX_DIR=/w/out/sfx

# [雷] 配樂比影片短時，-shortest 會把結尾卡整張砍掉。
# 先 aloop 無限循環再 atrim 到影片長度，並且不要用 -shortest。
#
# 音效放在版面切換點當點綴。音效是 8000Hz 單聲道，amix 前先 aformat 對齊
# 取樣率與聲道佈局，否則混完會變調。normalize=0 是為了不讓 amix 因為輸入數量
# 而把整體音量壓下去（預設會除以輸入數）。
ffmpeg -y -loglevel error -i "$TMP/silent.mp4" -i "$BGM" \
  -i "$SFX_DIR/sfx-011.wav" -i "$SFX_DIR/sfx-013.wav" -i "$SFX_DIR/sfx-018.wav" \
  -filter_complex "\
    [1:a]aloop=loop=-1:size=2000000000,atrim=0:$DUR,afade=t=in:st=0:d=2,afade=t=out:st=$FO:d=3,\
         aformat=sample_rates=44100:channel_layouts=stereo[music];\
    [2:a]aformat=sample_rates=44100:channel_layouts=stereo,adelay=6000|6000,volume=0.75[s1];\
    [3:a]aformat=sample_rates=44100:channel_layouts=stereo,adelay=21000|21000,volume=0.75[s2];\
    [4:a]aformat=sample_rates=44100:channel_layouts=stereo,adelay=36000|36000,volume=0.75[s3];\
    [music][s1][s2][s3]amix=inputs=4:duration=first:normalize=0[a]" \
  -map 0:v -map "[a]" -threads 2 -c:v libx264 -preset veryfast \
  -c:a aac -b:a 192k -movflags +faststart "$OUT/rexnebular-cht-promo.mp4"

echo "=== 完成：$THEME_NAME ==="
ffprobe -v error -select_streams v -show_entries stream=width,height,duration -of default=nw=1 "$OUT/rexnebular-cht-promo.mp4"
ffprobe -v error -select_streams a -show_entries stream=duration -of default=nw=1 "$OUT/rexnebular-cht-promo.mp4"
ls -la "$OUT"
