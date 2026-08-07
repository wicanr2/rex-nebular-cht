#!/bin/bash
# 開發用 Linux 建置（驗證中文路徑、截圖、錄影都用這顆）。
# 打包走各平台自己的腳本：Windows → build_windows.sh，macOS → .github/workflows/build-macos.yml。
set -e
cd /w/scummvm-src

echo "=== configure ==="
# [HARD] --disable-mt32emu：MADS 引擎沒有 MIDI 路徑（sound.cpp:45 直接 OPL::Config::create()，
# 全引擎 grep MidiDriver/MidiParser/detectDevice 零命中），mt32emu 編進去對這款完全無效，
# 只是把 binary 撐肥。2026-08-07 用頻譜圖比對實測定案，別再開回來。
./configure --disable-all-engines --enable-engine=mads --disable-mt32emu \
            --disable-debug --enable-release

# [HARD] configure 偵測不到函式庫不會報錯，只會安靜把選項關掉 —— 「編得過」不等於「有編進去」。
echo "=== 反查 config.mk ==="
grep -E "^(USE_FLAC|USE_VORBIS|USE_MAD|USE_PNG|USE_FREETYPE2) " config.mk || true
# mt32emu 是反向反查：它不該在
if grep -q "^USE_MT32EMU = 1" config.mk; then
    echo "### USE_MT32EMU = 1 —— 這款用不到，configure 選項沒生效 ###"
    exit 3
fi
echo "  ✓ 沒有 USE_MT32EMU"

echo "=== make ==="
make -j"$(nproc)"

echo "=== build 完成 ==="
file scummvm
ls -la scummvm
