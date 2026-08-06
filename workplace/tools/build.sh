#!/bin/bash
set -e
cd /w/scummvm-src
echo "=== configure ==="
./configure --disable-all-engines --enable-engine=mads --enable-mt32emu --disable-debug --enable-release
echo "=== configure 反查關鍵 USE_* 旗標 ==="
grep -E "^(USE_MT32EMU|USE_FLAC|USE_VORBIS|USE_MAD|USE_PNG|USE_FREETYPE2) " config.mk || true
echo "=== make ==="
make -j"$(nproc)"
echo "=== build 完成,binary 資訊 ==="
file scummvm
ls -la scummvm
