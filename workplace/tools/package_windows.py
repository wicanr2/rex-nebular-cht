#!/usr/bin/env python3
"""打《錯體奇航》繁中化的 Windows 交付包。

編碼相關的每一條都是「在 Linux 開發機上完全測不出來、到玩家端才爆」的那種，
所以規則寫死在這裡，並由 check_windows_zip.py 逐條驗（那支還做過正對照）。

六條：
  1. 包內檔名一律 ASCII，且 zip entry 強制帶 UTF-8 旗標（bit 11）
     —— zip 格式沒有檔名編碼欄位，繁中 Windows 看到沒旗標就用 CP950 解讀 UTF-8 bytes，
        運氣差時那串 bytes 在 CP950 是非法序列 → 解壓工具直接跳過該檔 → 玩家說「檔案不見了」
  2. .bat 換行 CRLF
  3. .bat 內容純 ASCII（中文提示放 README，不在 .bat 裡 echo）
  4. .bat 帶 if errorlevel 1 + pause，失敗時玩家看得到訊息
  5. README 存 UTF-8 with BOM（沒 BOM 的話舊記事本當 ANSI 解讀 → 中文全亂）
  6. 附預先寫好的靜態 scummvm.ini，鎖 gui_language=en；ini 走相對路徑、寫在包內，
     不污染玩家全域 ScummVM 設定

[雷] 別用「先 cat 再轉檔」的兩段式寫法 —— 中間那步靜默失敗時檔案看起來正常，
     只有拿到 Windows 開才發現編碼錯。這裡一律一次寫對。
"""
import os
import shutil
import sys
import time
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

BAT = """@echo off
cd /d "%~dp0"

if not exist "game\\global.hag" (
  echo.
  echo   Game data not found.
  echo   Copy your Rex Nebular files into the "game" folder,
  echo   then run this again. See README-CHT.txt for details.
  echo.
  pause
  exit /b 1
)

scummvm.exe --config=scummvm.ini --path=game --auto-detect --extrapath=cht-data
if errorlevel 1 (
  echo.
  echo   ScummVM exited with an error.
  echo   See README-CHT.txt for troubleshooting.
  echo.
  pause
)
"""

README = """錯體奇航（Rex Nebular and the Cosmic Gender Bender）繁體中文化
================================================================

怎麼玩
------

1. 把你的遊戲檔（global.hag、section1.hag ~ section9.hag、SECTION0.HAG、
   *.RES、asound.* 等）整份複製到本資料夾底下的 game 資料夾。
2. 雙擊 PLAY-REX-CHT.bat。

本包不含遊戲本體，你需要自備。


中文是怎麼開的
--------------

中文的開關就是 cht-data 裡那兩個檔在不在：

  cht-data\\rex_big5.fnt   自製點陣字型（倚天字形）
  cht-data\\rex_cht.tsv    譯文碼表

把它們移走，遊戲就變回英文原版，不需要改任何設定。
不必也不要去改 ScummVM 的語言選項——這款遊戲在 ScummVM 的
detection table 裡全部登記為英文，設成別的語言反而會讓辨識行為改變。


包裡有什麼
----------

  scummvm.exe          自編的 ScummVM（只含 MADS 引擎，已套繁中化修改）
  SDL2.dll             SDL2（自原始碼交叉編譯）
  scummvm.ini          設定檔。設定只寫在這個檔裡，不會動到你系統上
                       其他 ScummVM 的設定
  cht-data\\            譯文與字型
  game\\                你的遊戲檔放這裡
  themes\\              ScummVM 介面主題


出問題的話
----------

視窗一閃就不見：直接雙擊 PLAY-REX-CHT.bat 會停在錯誤訊息，
把訊息記下來。若是「找不到遊戲」，通常是 game 資料夾裡少了 global.hag。

畫面有中文但標點怪怪的：確認 cht-data 兩個檔都完整複製了，
只複製其中一個會讓部分字掉回英文字型。

存檔放哪：跟 scummvm.ini 同一層的 saves 資料夾。

聲音
----

預設是 Sound Blaster 配置，音樂與音效都開：

  音樂   AdLib FM 合成（SB 卡上就是這顆 YM3812 晶片）
  音效   數位取樣音效（SB 的 DAC 那一層）

想調音量改 scummvm.ini 裡的 music_volume / sfx_volume（0-255）。

這款不支援 MT-32：遊戲雖然附了 Roland 驅動（rsound.*），但那是 DOS
執行檔，ScummVM 的 MADS 引擎只重新實作了 AdLib 那一支，沒有 MIDI 輸出路徑。
設成 MT-32 不會有效果，會安靜地退回 AdLib。


授權
----

本包中，ScummVM 及其修改依 GPLv3 授權；譯文、碼表、點陣字型為本專案製作。
遊戲原作 (c) 1992 MicroProse Software, Inc.，不包含在本包內。
"""

# Sound Blaster 在這款是兩層，兩層 ScummVM 都有實作，這裡明確寫死免得靠預設值：
#   音樂  SB 卡上的 YM3812（跟 AdLib 是同一顆 FM 晶片）
#         → engines/mads/sound.cpp:45 的 OPL 模擬，資料是 asound.001-009
#   音效  SB 的 DAC
#         → engines/mads/audio.cpp:92 playSound() → FAB 解壓 → makeRawStream → mixer
#           資料是 REX009.DSR（22 筆）與 ACT002.DSR（13 筆），封在 HAG 內
# MADS 沒有 MIDI 路徑，所以 music_driver 除了 adlib 沒有別的有意義的選擇（見 docs/40-packaging.md）。
INI = """[scummvm]
gui_language=en
gfx_mode=surfacesdl
fullscreen=false
savepath=./saves
music_driver=adlib
music_volume=192
sfx_volume=255
speech_volume=255
"""


class Utf8ZipInfo(zipfile.ZipInfo):
    """強制帶 UTF-8 旗標（bit 11）的 entry。

    [雷] 直接設 `zi.flag_bits |= 0x800` 沒有用 —— ZipFile.writestr() 內部會把
    flag_bits 歸零再重算，設好的值被靜默丟掉（Python 3.12 實測：寫入前 0x800，
    寫入後 0x0）。而檔案照樣產出、大小正常，只有解析 zip 結構才看得出來。
    要改的是 CPython 真正拿來決定旗標的那個 hook。

    純 ASCII 檔名本來就不需要這個旗標（規則 1 已保證檔名全 ASCII），設它是保險：
    日後有人加了中文檔名，至少不會退回「繁中 Windows 靜默跳過該檔」那個老問題。
    """

    def _encodeFilenameFlags(self):
        return self.filename.encode("utf-8"), self.flag_bits | 0x800


def add(z, arcname, data, mtime):
    zi = Utf8ZipInfo(arcname, date_time=mtime)
    zi.compress_type = zipfile.ZIP_DEFLATED
    zi.external_attr = 0o644 << 16
    z.writestr(zi, data)


def main():
    tree = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "mingw-tree")
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "dist-all", "rexnebular-cht-win64.zip")
    os.makedirs(os.path.dirname(out), exist_ok=True)

    # build_windows.sh 收尾會把 strip 過的 exe 與「所有非系統 DLL」放進 win-deps/。
    # 直接吃那個目錄，而不是各自去猜要帶哪些檔 —— 該帶什麼是由 objdump 問出來的，不是我記的。
    deps = os.path.join(ROOT, "build", "win-deps")
    exe = os.path.join(deps, "scummvm.exe")
    if not os.path.isfile(exe):
        sys.exit("### 找不到 build/win-deps/scummvm.exe，先跑 tools/build_windows.sh ###")

    mtime = time.localtime(os.path.getmtime(exe))[:6]

    files = []          # (arcname, 實體路徑)
    files.append(("scummvm.exe", exe))
    for name in sorted(os.listdir(deps)):
        if name.lower().endswith(".dll"):
            files.append((name, os.path.join(deps, name)))

    # 中文資料以 repo 的 cht-data/ 為單一真相：三平台的包都從這裡取，
    # 才不會出現「Linux 包的譯文比 Windows 包新」這種對不上的情況。
    chtdir = os.path.join(ROOT, "..", "cht-data")
    for name in ("rex_cht.tsv", "rex_big5.fnt", "ENGINE.txt"):
        p = os.path.join(chtdir, name)
        if not os.path.isfile(p):
            sys.exit(f"### 缺 {p} ###")
        files.append((f"cht-data/{name}", p))

    # 主題：只挑用得到的。全套 engine-data 約 59MB，只編 MADS 時絕大多數用不到
    # （fonts-cjk.dat 37MB、Roland_SC-55.sf2 3.2MB…）。
    # scummremastered.zip 是預設主題，漏帶會 fallback to builtin。
    for name in ("scummremastered.zip", "scummmodern.zip", "scummclassic.zip"):
        p = os.path.join(tree, "gui", "themes", name)
        if os.path.isfile(p):
            files.append((f"themes/{name}", p))
    for name in ("fonts.dat", "encoding.dat"):
        for cand in (os.path.join(tree, "gui", "themes", name), os.path.join(tree, "dists", "engine-data", name)):
            if os.path.isfile(cand):
                files.append((f"themes/{name}", cand))
                break

    # [HARD] 規則 1：包內檔名一律 ASCII
    bad = [a for a, _ in files if any(ord(c) > 127 for c in a)]
    if bad:
        sys.exit(f"### 這些檔名含非 ASCII，繁中 Windows 可能亂碼或跳過：{bad} ###")

    if os.path.exists(out):
        os.remove(out)

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for arc, path in files:
            with open(path, "rb") as f:
                add(z, arc, f.read(), mtime)
        # 規則 2/3/4：.bat 純 ASCII + CRLF + errorlevel + pause
        add(z, "PLAY-REX-CHT.bat", BAT.replace("\n", "\r\n").encode("ascii"), mtime)
        # 規則 5：README UTF-8 with BOM + CRLF
        add(z, "README-CHT.txt", README.replace("\n", "\r\n").encode("utf-8-sig"), mtime)
        # 規則 6：靜態 ini，不由 .bat echo 產生
        add(z, "scummvm.ini", INI.replace("\n", "\r\n").encode("utf-8"), mtime)
        # 讓 game/ 在解壓後就存在，玩家一眼知道檔案放哪
        add(z, "game/PUT-GAME-FILES-HERE.txt",
            ("Copy your Rex Nebular data files into this folder.\r\n"
             "global.hag, section1.hag ... section9.hag, SECTION0.HAG, *.RES, asound.*\r\n").encode("ascii"),
            mtime)

    print(f"=== 產出 {out} ({os.path.getsize(out):,} bytes) ===")
    with zipfile.ZipFile(out) as z:
        for i in z.infolist():
            print(f"  {i.file_size:>9,}  {i.filename}")


if __name__ == "__main__":
    main()
