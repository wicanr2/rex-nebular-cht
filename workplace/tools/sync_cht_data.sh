#!/usr/bin/env bash
# 把 cht-data/ 的中文資料同步到遊戲目錄，並反查引擎實際讀到的版本。
#
# 為什麼需要這支：中文資料有**兩份**——
#   cht-data/         版控裡的來源（重烘字型、合併譯文都改這裡）
#   workplace/game/   引擎執行時實際讀的（跟遊戲資料放在一起）
# 沒有同步機制的下場：改完 cht-data 直接跑實機驗證，看到的還是舊資料。
# 2026-08-07 就這樣白跑了一輪 —— 補了 199 則動畫訊息、字型重烘成 2409 字，
# 實機 log 卻印「替換表 4357 筆、字型 2394 字」，而所有截圖都「看起來正常」，
# 因為那些畫面本來就不含新增的內容。**沒有反查，同步失敗是靜默的。**
#
# 用法：sync_cht_data.sh [遊戲目錄]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/../../cht-data"
DEST="${1:-$HERE/../game}"

[ -d "$SRC" ]  || { echo "### 找不到 $SRC ###"; exit 2; }
[ -d "$DEST" ] || { echo "### 找不到 $DEST ###"; exit 2; }

for f in rex_cht.tsv rex_big5.fnt; do
    [ -s "$SRC/$f" ] || { echo "### $SRC/$f 不存在或是空的 ###"; exit 3; }
    cp "$SRC/$f" "$DEST/$f"
done

# [HARD] 反查：cp 成功不等於內容一致（來源可能自己就是舊的）。比 md5。
for f in rex_cht.tsv rex_big5.fnt; do
    a=$(md5sum "$SRC/$f"  | cut -d' ' -f1)
    b=$(md5sum "$DEST/$f" | cut -d' ' -f1)
    [ "$a" = "$b" ] || { echo "### $f 同步後 md5 不一致 ###"; exit 4; }
    echo "  ✓ $f  ${a:0:12}"
done

# 印出兩個數字，方便跟引擎啟動時的 [CHT] 那行對照。
ROWS=$(grep -avc '^#' "$DEST/rex_cht.tsv")
GLYPHS=$(python3 -c "
import struct, sys
d = open('$DEST/rex_big5.fnt','rb').read()
assert d[:4] == b'RXCF', 'not RXCF'
print(struct.unpack('<H', d[6:8])[0])
")
echo "=== 同步完成：替換表 $ROWS 筆、字型 $GLYPHS 字 ==="
echo "    引擎啟動時（-d 1）應印出同樣的數字，對不上就是還在讀別處的舊檔。"
