#!/usr/bin/env bash
# 《錯體奇航》繁中化推廣片 v2 —— 用真實遊玩錄影，不是靜態截圖拼的。
#
# 與 v1 的差別，以及為什麼要改：
#   v1  靜態截圖卡片 + 後製把音效混到時間軸上（位置是猜的）
#   v2  x11grab 錄畫面 + PulseAudio null sink 錄聲，同一個 ffmpeg 行程，時間軸天生對齊
# 音效是遊戲事件觸發的，錄下來它就落在該響的那一刻。
#
# [雷] 不能用 SDL 的 disk audio driver 錄。它是「盡快把 mixer 輸出寫檔」，不受真實時間
#      約束 —— 實測 110 秒的遊玩錄出 397 秒音訊，音畫差 3.6 倍。null sink 沒有實體硬體，
#      但按真實時間消耗取樣（模擬音效卡時鐘），這才是對的。
#
# 聲音是 Sound Blaster 的兩層，都在錄影裡自然發生：
#   音樂  SB 卡上的 YM3812 FM 合成（asound.001-009 → engines/mads/sound.cpp:45 的 OPL）
#   音效  SB 的 DAC（REX009.DSR → engines/mads/audio.cpp:92）
#
# [HARD] 不用 zoompan —— 它的 d 是「每個輸入幀輸出 d 幀」，配上前置 fps 會變成
#        (FPS*S)² 幀，6 秒 25fps ≈ 22500 幀，CPU 燒好幾分鐘。
set -eu

THEME_NAME="太空艙青"
BG_DEEP='#08141a'; BG_LITE='#244148'
ACCENT='#4ec9d9'; ACCENT_DIM='#2a7c88'
TEXT='#d1dae3'; DIM='#7f95a3'
FB=/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc
FR=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
W=1280; H=720; FPS=25
SHOT=/w/out; OUT=/w/out/promo; TMP=/tmp/promo2
GP=/w/out/gp-sync
mkdir -p "$OUT" "$TMP"

[ -s "$GP/raw.mkv" ] || { echo "### 沒有遊玩錄影，先跑 tools/record_gameplay_sync.sh ###"; exit 2; }
# [HARD] 錄影必須音畫同步，否則遊玩片段的音效會落在錯的地方
VD=$(ffprobe -v error -select_streams v -show_entries stream=duration -of csv=p=0 "$GP/raw.mkv")
AD=$(ffprobe -v error -select_streams a -show_entries stream=duration -of csv=p=0 "$GP/raw.mkv" 2>/dev/null || echo 0)
awk -v v="$VD" -v a="$AD" 'BEGIN{d=(v>a?v-a:a-v); if (d>3) {print "### 音畫差 "d"s，這份錄影沒同步 ###"; exit 1}}' \
  || { echo "  用 tools/record_gameplay_sync.sh 重錄（PulseAudio null sink 才有真實時鐘）"; exit 2; }

# ---------- 靜態版面 ----------
card() { # $1 out  $2 中標  $3 英標  $4 副標
  convert -size ${W}x${H} "radial-gradient:${BG_LITE}-${BG_DEEP}" \
    -font "$FB" -gravity center \
    -fill "$ACCENT_DIM" -pointsize 96 -annotate +3+3 "$2" \
    -fill "$ACCENT"     -pointsize 96 -annotate +0+0 "$2" \
    -font "$FR" -fill "$TEXT" -pointsize 34 -annotate +0+92 "$3" \
    -fill "$DIM" -pointsize 26 -annotate +0+160 "$4" "$1"
}

dcard() { # $1 out  $2 中文譯文  $3 英文原文
  convert -size ${W}x${H} "gradient:${BG_DEEP}-${BG_LITE}" \
    -font "$FB" -fill "${ACCENT_DIM}" -pointsize 300 -gravity northwest -annotate +40-60 '"' \
    -font "$FR" -fill "$TEXT" -pointsize 44 -gravity west -annotate +110+0 "$2" \
    -font "$FR" -fill "$DIM"  -pointsize 24 -gravity southwest -annotate +112+90 "$3" "$1"
}

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

statcard() { # $1 out  $2 標題  $3 大數字  $4 說明
  convert -size ${W}x${H} "radial-gradient:${BG_LITE}-${BG_DEEP}" \
    -font "$FR" -fill "$DIM" -gravity center -pointsize 30 -annotate +0-130 "$2" \
    -font "$FB" -fill "$ACCENT" -gravity center -pointsize 150 -annotate +0-20 "$3" \
    -font "$FR" -fill "$TEXT" -gravity center -pointsize 30 -annotate +0+100 "$4" "$1"
}

# 靜態卡片：配上錄影音軌的某一段當背景音樂。
# 所有片段的音訊參數必須一致，concat demuxer 才接得起來。
clip() { # $1 png  $2 mp4  $3 秒  $4 音訊起點秒
  local FO; FO=$(awk "BEGIN{print $3-0.5}")
  ffmpeg -y -loglevel error -loop 1 -i "$1" -ss "$4" -i "$GP/raw.mkv" -t "$3" -r $FPS \
    -vf "fade=t=in:st=0:d=0.5,fade=t=out:st=$FO:d=0.5,format=yuv420p" \
    -af "aformat=sample_rates=44100:channel_layouts=stereo,volume=0.85" \
    -map 0:v -map 1:a -threads 2 -c:v libx264 -preset veryfast -pix_fmt yuv420p \
    -c:a aac -b:a 192k -ar 44100 -ac 2 "$2"
}

# 遊玩片段：裁掉 Xvfb 的黑邊（遊戲畫面在 1024x768 裡是 640x400 @ +192+180），
# 用 neighbor 放大保持 pixel art 銳利，再 pad 成 16:9。
# 遊玩片段：畫面與音訊從同一時間點一起裁 —— 這樣音效才落在它該響的那一刻，
# 而不是後製猜一個位置塞進去。這是整支 v2 的重點。
gameplay() { # $1 起點秒  $2 長度  $3 out  $4 字幕
  local FO; FO=$(awk "BEGIN{print $2-0.5}")
  ffmpeg -y -loglevel error -ss "$1" -t "$2" -i "$GP/raw.mkv" \
    -vf "crop=640:400:192:180,scale=1152:720:flags=neighbor,pad=${W}:${H}:64:0:black,\
drawbox=y=ih-92:w=iw:h=92:color=black@0.72:t=fill,\
drawtext=fontfile=$FR:text='$4':fontcolor=#d1dae3:fontsize=32:x=(w-text_w)/2:y=h-62,\
fade=t=in:st=0:d=0.5,fade=t=out:st=$FO:d=0.5,format=yuv420p" \
    -af "aformat=sample_rates=44100:channel_layouts=stereo" \
    -r $FPS -threads 2 -c:v libx264 -preset veryfast -pix_fmt yuv420p \
    -c:a aac -b:a 192k -ar 44100 -ac 2 "$3"
}

# ===== 分鏡 =====
card       "$TMP/00.png" '錯體奇航' 'Rex Nebular and the Cosmic Gender Bender' 'MicroProse 1992 ・ 繁體中文化'
dcard      "$TMP/02.png" '夢到自己被人打下來……然後一頭撞進……糟了！' 'I dreamed I was shot down . . . and crashed into the . . . Uh oh!'
split_ba   "$TMP/04.png" "$SHOT/clean-en.png" "$SHOT/clean-cht.png" '指令表 ・ 物品欄 ・ 對白 全中文'
statcard   "$TMP/06.png" '這一路上的每一句話' '4357' '則對白與詞條 ・ 2394 字自製點陣字型'
card       "$TMP/99.png" '錯體奇航' 'Rex Nebular and the Cosmic Gender Bender' '繁體中文化 ・ 倚天點陣字 ・ 三平台'

# 靜態卡片的音訊各取一段不重疊的區間，接起來不會聽到同一句重複
clip     "$TMP/00.png" "$TMP/c00.mp4" 6 40
gameplay 58  8 "$TMP/c01.mp4" '太空打撈員雷克斯・尼布勒，船沉在一顆只剩女人的星球上'
clip     "$TMP/02.png" "$TMP/c02.mp4" 5 66
gameplay 72  7 "$TMP/c03.mp4" '指令表、物品欄、旁白，全部翻成繁體中文'
clip     "$TMP/04.png" "$TMP/c04.mp4" 5 79
gameplay 88  6 "$TMP/c05.mp4" '聲音是原版 Sound Blaster：FM 音樂配上數位音效'
clip     "$TMP/06.png" "$TMP/c06.mp4" 5 94
clip     "$TMP/99.png" "$TMP/c99.mp4" 6 99

LIST="$TMP/list.txt"; : > "$LIST"
for f in c00 c01 c02 c03 c04 c05 c06 c99; do echo "file '$TMP/$f.mp4'" >> "$LIST"; done

# 每個片段都自帶音訊（遊玩片段是它自己那一刻的聲音），concat 直接接起來。
# 不再事後蓋一層背景音樂 —— 那會把好不容易對齊的音效壓掉。
ffmpeg -y -loglevel error -f concat -safe 0 -i "$LIST" \
  -threads 2 -c:v libx264 -preset veryfast -pix_fmt yuv420p \
  -c:a aac -b:a 192k -ar 44100 -ac 2 "$TMP/joined.mp4"

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TMP/joined.mp4")
FO=$(awk "BEGIN{print $DUR-3}")

# 收尾統一響度 + 頭尾淡入淡出。不用 -shortest（它會把結尾卡整張砍掉）。
ffmpeg -y -loglevel error -i "$TMP/joined.mp4" \
  -af "loudnorm=I=-18:TP=-2,afade=t=in:st=0:d=1.5,afade=t=out:st=$FO:d=3" \
  -c:v copy -c:a aac -b:a 192k -movflags +faststart "$OUT/rexnebular-cht-promo.mp4"

echo "=== 完成：$THEME_NAME（真實遊玩錄影版）==="
ffprobe -v error -select_streams v -show_entries stream=width,height,duration -of default=nw=1 "$OUT/rexnebular-cht-promo.mp4"
ffprobe -v error -select_streams a -show_entries stream=duration,codec_name -of default=nw=1 "$OUT/rexnebular-cht-promo.mp4"
ls -la "$OUT"
