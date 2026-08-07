#!/usr/bin/env bash
# 打「完整版」：中文化的 ScummVM ＋ **遊戲本體**，三平台，**只存本機**。
#
# 為什麼要跟 dist-all 分開放
# ---------------------------
# `dist-all/` 裡混著兩種東西：patch zip 與 Windows/macOS 包是公開散布用的（不含遊戲），
# 而 `RexNebular-CHT-x86_64.AppImage` **含 56 個遊戲資料檔** —— 這件事只寫在
# package_linux.sh 的第一行註解裡，包本身看不出來，而 README 又直接指路它。
# 兩種包放同一個目錄、名字只差在副檔名，發 Release 時傳錯一顆就是版權事故。
#
# 所以完整版一律輸出到 **repo 之外**的目錄。不是靠 .gitignore ——
# 這個專案已經證明過 .gitignore 對已追蹤檔案無效、而 check-ignore 的正對照
# 只驗新檔，四個含原版配樂的錄影就是這樣進了公開 repo（見 docs/40-packaging.md）。
# 放在版本庫之外，是唯一不依賴任何規則設定正確的做法。
#
# 用法：package_full_local.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$HERE/.."
ROOT="$W/.."
DIST="$W/dist-all"
GAME="$W/game"

# [HARD] repo 之外。寫死不給參數 —— 給參數就有人會傳 dist-all 進來。
OUT="/home/anr2/scummvm/rexnebular-full-local"

# 反查這個路徑真的在版本庫外，而不是「我以為它在外面」。
if git -C "$ROOT" check-ignore -q "$OUT" 2>/dev/null || \
   git -C "$ROOT" ls-files --error-unmatch "$OUT" >/dev/null 2>&1; then
    echo "### $OUT 落在版本庫內 —— 完整版不能放這 ###"; exit 2
fi
case "$(realpath "$OUT")/" in
    "$(realpath "$ROOT")"/*) echo "### $OUT 在 repo 底下 ###"; exit 2 ;;
esac

# 遊戲資料：56 個檔（floppy DOS 版）。少一個就不是完整版。
EXPECT_GAME=56
count_game() {   # $1 目錄
    find "$1" -maxdepth 1 -type f \
        \( -iname '*.hag' -o -iname '*.res' -o -iname '?sound.[0-9][0-9][0-9]' \
           -o -iname 'digital.aga' \) | wc -l
}
n=$(count_game "$GAME")
[ "$n" = "$EXPECT_GAME" ] || { echo "### 來源 $GAME 只有 $n 個遊戲檔，應為 $EXPECT_GAME ###"; exit 3; }
echo "=== 來源遊戲資料 $n 個檔 ==="

mkdir -p "$OUT"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# ---------- Linux ----------
# 現成的 AppImage 已經含遊戲（AppRun 直接指 usr/share/rexnebular-game）。
# 只是改個名字，讓「這顆含遊戲」寫在檔名上而不是只寫在某支腳本的註解裡。
cp "$DIST/RexNebular-CHT-x86_64.AppImage" "$OUT/RexNebular-CHT-FULL-x86_64.AppImage"
chmod +x "$OUT/RexNebular-CHT-FULL-x86_64.AppImage"
( cd "$TMP" && "$OUT/RexNebular-CHT-FULL-x86_64.AppImage" --appimage-extract >/dev/null 2>&1 )
n=$(count_game "$TMP/squashfs-root/usr/share/rexnebular-game")
[ "$n" = "$EXPECT_GAME" ] || { echo "### AppImage 裡只有 $n 個遊戲檔 ###"; exit 4; }
echo "  ✓ Linux   AppImage        遊戲檔 $n"
rm -rf "$TMP/squashfs-root"

# ---------- Windows ----------
# PLAY-REX-CHT.bat 本來就檢查 game\global.hag 再啟動，把資料放進去就完事，
# 啟動器一個字都不用改。
rm -rf "$TMP/win"; mkdir -p "$TMP/win"
unzip -q "$DIST/rexnebular-cht-win64.zip" -d "$TMP/win"
cp "$GAME"/*.hag "$GAME"/*.HAG "$GAME"/*.res "$GAME"/*.RES \
   "$GAME"/?sound.[0-9][0-9][0-9] "$GAME"/digital.aga "$TMP/win/game/" 2>/dev/null || true
rm -f "$TMP/win/game/PUT-GAME-FILES-HERE.txt"
n=$(count_game "$TMP/win/game")
[ "$n" = "$EXPECT_GAME" ] || { echo "### Windows 包只塞進 $n 個遊戲檔 ###"; exit 5; }
# [雷] 這裡原本用 `zip -q -r -UN=UTF8`，規則 1 當場不過 —— `-UN=UTF8` 是
# 「檔名有非 ASCII 時用 UTF-8 存」，純 ASCII 檔名它就不設旗標，而檢查要求每個
# entry 都帶。六條編碼規則對完整版一樣適用（本機解開一樣是繁中 Windows 在解），
# 所以改走 package_windows.py 用的那個 Utf8ZipInfo hook。
python3 - "$TMP/win" "$OUT/RexNebular-CHT-FULL-win64.zip" <<'PY'
import os, sys, time, zipfile

class Utf8ZipInfo(zipfile.ZipInfo):
    # 直接設 flag_bits |= 0x800 會被 writestr() 內部歸零重算（見 package_windows.py）
    def _encodeFilenameFlags(self):
        return self.filename.encode("utf-8"), self.flag_bits | 0x800

src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for d, _dirs, fs in os.walk(src):
        for fn in sorted(fs):
            p = os.path.join(d, fn)
            arc = os.path.relpath(p, src).replace(os.sep, "/")
            zi = Utf8ZipInfo(arc, date_time=time.localtime(os.path.getmtime(p))[:6])
            zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = 0o644 << 16
            with open(p, "rb") as f:
                z.writestr(zi, f.read())
PY
# [HARD] 反查：規則 1–6 對完整版也要過，不能因為「只給自己用」就跳過。
python3 "$HERE/check_windows_zip.py" "$OUT/RexNebular-CHT-FULL-win64.zip" >/dev/null \
    || { echo "### Windows 完整版沒過六條編碼規則 ###"; exit 5; }
echo "  ✓ Windows zip             遊戲檔 $n，六條編碼規則通過"

# ---------- macOS ----------
# [HARD] 不動平台自己的啟動機制：不改 Info.plist、不塞東西進 Contents/MacOS/。
# 遊戲放在 .app **旁邊**，配一支 .command 當啟動器 —— 那就是「程式旁邊的一支腳本」。
rm -rf "$TMP/mac"; mkdir -p "$TMP/mac"
tar xzf "$DIST/RexNebular-CHT-macos-universal.tar.gz" -C "$TMP/mac"
mkdir -p "$TMP/mac/game"
cp "$GAME"/*.hag "$GAME"/*.HAG "$GAME"/*.res "$GAME"/*.RES \
   "$GAME"/?sound.[0-9][0-9][0-9] "$GAME"/digital.aga "$TMP/mac/game/" 2>/dev/null || true
n=$(count_game "$TMP/mac/game")
[ "$n" = "$EXPECT_GAME" ] || { echo "### macOS 包只塞進 $n 個遊戲檔 ###"; exit 6; }
cat > "$TMP/mac/PLAY-REX-CHT.command" <<'CMD'
#!/bin/bash
# 雙擊執行。第一次開啟前若被 Gatekeeper 擋下：
#   xattr -dr com.apple.quarantine "$(dirname "$0")/ScummVM.app"
cd "$(dirname "$0")"
[ -f game/global.hag ] || { echo "找不到 game/global.hag"; read -r; exit 1; }
exec ./ScummVM.app/Contents/MacOS/scummvm \
    --path=game --auto-detect \
    --extrapath=ScummVM.app/Contents/Resources
CMD
chmod +x "$TMP/mac/PLAY-REX-CHT.command"
( cd "$TMP/mac" && tar czf "$OUT/RexNebular-CHT-FULL-macos-universal.tar.gz" . )
echo "  ✓ macOS   tar.gz          遊戲檔 $n"
echo "    [未驗證] .command 啟動器沒有 macOS 機器可測，路徑是照 bundle 結構推的"

cat > "$OUT/README-LOCAL-ONLY.txt" <<'TXT'
本機完整版 —— 不可散布
======================

這個目錄裡的三個包都含 Rex Nebular 的遊戲資料（56 個檔），
那是 MicroProse 的著作權素材。**只供自己在自己的機器上遊玩**，
不要上傳、不要放進 GitHub Release、不要傳給別人。

公開散布的版本在 workplace/dist-all/，那些不含遊戲資料
（唯一的例外是 dist-all 裡那顆 RexNebular-CHT-x86_64.AppImage，
 它跟這裡的 FULL 版是同一顆，發布前必須先處理）。

  RexNebular-CHT-FULL-x86_64.AppImage        chmod +x 後直接執行
  RexNebular-CHT-FULL-win64.zip              解開後雙擊 PLAY-REX-CHT.bat
  RexNebular-CHT-FULL-macos-universal.tar.gz 解開後雙擊 PLAY-REX-CHT.command

重出：workplace/tools/package_full_local.sh
TXT

echo
echo "=== 完整版輸出到 $OUT ==="
ls -la "$OUT" | tail -5
