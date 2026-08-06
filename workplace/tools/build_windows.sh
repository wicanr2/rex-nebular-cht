#!/usr/bin/env bash
# 交叉編譯 scummvm.exe（Windows x86_64，MADS-only，含繁中化 patch）。
#
# SDL2 是容器裡從原始碼交叉編的（見 docker/Dockerfile.mingw），不是官方預編譯 devel 包。
#
# [HARD] configure 偵測不到函式庫不會報錯，只會安靜把選項關掉。「編得過」不等於「有編進去」，
#        所以收尾一定要反查 config.mk，而且只反查「這款真的用得到」的那幾項。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TREE="${1:-$ROOT/build/mingw-tree}"
IMG="${IMG:-rex-mingw:latest}"

[ -f "$TREE/configure" ] || { echo "### $TREE 不是 ScummVM 樹，先跑 tools/apply_patches.sh ###"; exit 2; }

# MADS 的音樂只走 OPL（engines/mads/sound.cpp:45 建構子直接 OPL::Config::create()），
# 全引擎沒有任何 MidiDriver 使用 → Munt(mt32emu) 對這款完全無用，編進去只是把 exe 撐肥。
# 其餘外部媒體庫同理：nebular 是 1992 floppy 版，音樂 AdLib、動畫自帶解碼，用不到
# vorbis/flac/mad/theora。zlib 保留（存檔壓縮 + launcher 讀 .zip 主題）。
LEAN_FLAGS="
  --disable-ogg --disable-vorbis --disable-tremor --disable-flac --disable-mad
  --disable-faad --disable-mpcdec --disable-openmpt --disable-mikmod
  --disable-fluidsynth --disable-fluidlite --disable-sonivox
  --disable-theoradec --disable-vpx --disable-mpeg2 --disable-a52
  --disable-jpeg --disable-gif --disable-freetype2 --disable-fribidi
  --disable-libcurl --disable-cloud --disable-enet --disable-sdlnet
  --disable-discord --disable-sparkle --disable-lua --disable-tts"
# [雷] 這串等一下要嵌進 bash -c "..." 裡。變數裡的換行會直接變成該 script 的換行，
# 把 ./configure 的續行切斷 —— 第二行以後會被當成新指令（`--disable-ogg: command not found`），
# 而 configure 本身還是跑完了、還是產出 config.mk，看起來像成功。先壓成單行。
LEAN_FLAGS="$(echo $LEAN_FLAGS | tr -s ' ')"

# ScummVM 各版本的 configure 選項會 drift（2.8.0 就沒有 --disable-mpcdec），
# 傳一個它不認得的會讓整個 configure 直接 error 退出。先問它認得哪些再傳。
# [HARD] 被丟掉的一定要印出來 —— 靜默過濾等於把「flag 打錯字」變成看不見的問題。
echo "=== 過濾 configure 不認得的選項 ==="
KNOWN="$(docker run --rm --log-opt max-size=10m --log-opt max-file=3 \
  --user "$(id -u):$(id -g)" -v "$TREE:/src" -w /src "$IMG" ./configure --help 2>/dev/null \
  | grep -oE '^\s+--[a-z0-9-]+' | tr -d ' ')"
KEPT=""; DROPPED=""
for f in $LEAN_FLAGS; do
    if echo "$KNOWN" | grep -qx -- "$f"; then KEPT="$KEPT $f"; else DROPPED="$DROPPED $f"; fi
done
LEAN_FLAGS="$KEPT"
[ -n "$DROPPED" ] && echo "  這個 ScummVM 版本不認得，已略過：$DROPPED"
echo "  保留 $(echo $KEPT | wc -w) 個選項"

echo "=== configure ==="
# [HARD] mingw 編出來的 exe 預設動態連結 mingw 自己的 runtime（libwinpthread-1.dll、
# libgcc_s_seh-1.dll、libstdc++-6.dll）。那些不是 Windows 系統 DLL，玩家機器上沒有，
# 一開就是「找不到 libwinpthread-1.dll」—— 而這在 Linux 上完全測不出來。
# 靜態連結進去，包裡就只剩 SDL2.dll 一個外部依賴。
docker run --rm --log-opt max-size=10m --log-opt max-file=3 \
  --user "$(id -u):$(id -g)" -v "$TREE:/src" -w /src "$IMG" bash -c "
    set -e
    export LDFLAGS='-static-libgcc -static-libstdc++ -Wl,-Bstatic,--whole-archive -lwinpthread -Wl,--no-whole-archive,-Bdynamic'
    ./configure --host=x86_64-w64-mingw32 \
      --disable-all-engines --enable-engine=mads --disable-detection-full \
      --enable-release --disable-mt32emu $LEAN_FLAGS
  "

echo "=== [HARD] 反查 config.mk：要的東西有沒有真的編進去 ==="
docker run --rm --log-opt max-size=10m --log-opt max-file=3 \
  --user "$(id -u):$(id -g)" -v "$TREE:/src" -w /src "$IMG" bash -c '
    set -e
    fail=0
    grep -q "^ENABLE_MADS"     config.mk || { echo "  ✗ MADS engine 沒編入"; fail=1; }
    grep -q "^SDL_BACKEND = 1" config.mk || { echo "  ✗ SDL backend 沒偵測到（自編 SDL2 沒被找到？）"; fail=1; }
    grep -q "^USE_ZLIB = 1"    config.mk || { echo "  ✗ zlib 沒偵測到"; fail=1; }
    # 反向確認：刻意關掉的別又被打開（表示 flag 打錯字沒生效）
    grep -q "^USE_MT32EMU = 1" config.mk && { echo "  ✗ mt32emu 應該關掉卻開著"; fail=1; }
    [ "$fail" = 0 ] && echo "  ✓ MADS / SDL / zlib 都在，mt32emu 已關"
    exit $fail
  '

echo "=== make ==="
docker run --rm --log-opt max-size=10m --log-opt max-file=3 \
  --user "$(id -u):$(id -g)" -v "$TREE:/src" -w /src "$IMG" bash -c 'make -j"$(nproc)"'

echo "=== strip + 收集執行期 DLL ==="
# strip：未 strip 的 exe/dll 帶著整份 debug symbol（SDL2.dll 未 strip 是 14MB，strip 後約 1/10）
DEPS="$ROOT/build/win-deps"
rm -rf "$DEPS"; mkdir -p "$DEPS"
docker run --rm --log-opt max-size=10m --log-opt max-file=3 \
  --user "$(id -u):$(id -g)" -v "$TREE:/src" -v "$DEPS:/deps" -w /src "$IMG" bash -c '
    set -e
    cp scummvm.exe /deps/scummvm.exe
    cp /usr/x86_64-w64-mingw32/bin/SDL2.dll /deps/SDL2.dll
    x86_64-w64-mingw32-strip /deps/scummvm.exe /deps/SDL2.dll

    # [HARD] 用 objdump 問「它到底要什麼」，不要憑印象假設靜態連結成功了。
    # 系統 DLL 玩家一定有；其餘（mingw runtime）沒跟著包就是玩家端啟動失敗。
    SYS="KERNEL32|USER32|GDI32|SHELL32|ADVAPI32|WINMM|ole32|OLEAUT32|msvcrt|IMM32|VERSION|SETUPAPI|RPCRT4|SHLWAPI|WS2_32|dwmapi|UxTheme|comdlg32|COMCTL32|CFGMGR32|hid|d3d9|dxgi|OPENGL32"
    MISSING=""
    for exe in /deps/scummvm.exe /deps/SDL2.dll; do
      for dll in $(x86_64-w64-mingw32-objdump -p "$exe" | sed -n "s/.*DLL Name: //p" | sort -u); do
        case "$dll" in
          SDL2.dll) continue ;;
        esac
        if ! echo "$dll" | grep -qiE "^($SYS)\.dll$"; then
          if [ -f "/usr/lib/gcc/x86_64-w64-mingw32/12-posix/$dll" ]; then
            cp "/usr/lib/gcc/x86_64-w64-mingw32/12-posix/$dll" /deps/
            echo "  補進非系統 DLL：$dll"
          elif [ -f "/usr/x86_64-w64-mingw32/lib/$dll" ]; then
            cp "/usr/x86_64-w64-mingw32/lib/$dll" /deps/
            echo "  補進非系統 DLL：$dll"
          else
            MISSING="$MISSING $dll"
          fi
        fi
      done
    done
    if [ -n "$MISSING" ]; then
      echo "### 這些非系統 DLL 找不到實體，玩家端會啟動失敗：$MISSING ###"; exit 4
    fi
    echo "  外部依賴檢查：只剩系統 DLL 與包內附的"
  '

echo "=== 產物 ==="
ls -la "$DEPS"
file "$DEPS/scummvm.exe"
file "$DEPS/scummvm.exe" | grep -q 'PE32+' || { echo "### 不是 PE32+ x86-64 ###"; exit 3; }
echo "✓ scummvm.exe 交叉編譯完成"
