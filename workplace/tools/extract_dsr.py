#!/usr/bin/env python3
"""抽出 REX009.DSR 裡的數位音效（Sound Blaster DAC 那一層）。

格式照 ScummVM 的 engines/mads/audio.cpp:68-88 實作，不是猜的：

    uint16  entryCount
    每筆：  uint16 frequency        取樣率
            uint32 channels
            uint32 compSize         FAB 壓縮後大小
            uint32 uncompSize       解開後大小
            uint32 offset           在檔案內的位移
    資料本身 FAB 壓縮，解開後是 **unsigned 8-bit PCM**
    （audio.cpp:120 makeRawStream(..., Audio::FLAG_UNSIGNED)，沒有 FLAG_16BITS）

為什麼要自己解：「ScummVM 的 log 沒有 DSR 載入失敗的警告」是否定證據 ——
沒呼叫 playSound 也不會有警告。自己把資料解出來、看得到波形，才是正面證據。

用法：
    extract_dsr.py <遊戲目錄> <輸出目錄> [最多幾筆]
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mads_res import HagArchive, fab_decompress  # noqa: E402

DSR_NAME = "REX009.DSR"


def parse_dsr(data):
    count = struct.unpack_from("<H", data, 0)[0]
    entries = []
    pos = 2
    for _ in range(count):
        freq, channels, comp, uncomp, offset = struct.unpack_from("<HIIII", data, pos)
        pos += 18
        entries.append(dict(frequency=freq, channels=channels,
                            comp_size=comp, uncomp_size=uncomp, offset=offset))
    return entries


def wav_header(n_bytes, rate, bits=8, channels=1):
    """unsigned 8-bit PCM 正好是 WAV 的原生格式，不必轉換。"""
    return (b"RIFF" + struct.pack("<I", 36 + n_bytes) + b"WAVEfmt " +
            struct.pack("<IHHIIHH", 16, 1, channels, rate,
                        rate * channels * bits // 8, channels * bits // 8, bits) +
            b"data" + struct.pack("<I", n_bytes))


def main():
    game = sys.argv[1] if len(sys.argv) > 1 else "game"
    out = sys.argv[2] if len(sys.argv) > 2 else "out/sfx"
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    os.makedirs(out, exist_ok=True)

    arc = HagArchive(game)
    data = arc.read(DSR_NAME)
    if data is None:
        sys.exit(f"### HAG 裡找不到 {DSR_NAME} ###")
    print(f"{DSR_NAME}: {len(data):,} bytes")

    entries = parse_dsr(data)
    print(f"共 {len(entries)} 筆音效")

    ok = fail = 0
    sizes = []
    for i, e in enumerate(entries):
        if limit and i >= limit:
            break
        try:
            comp = data[e["offset"]:e["offset"] + e["comp_size"]]
            if len(comp) != e["comp_size"]:
                raise ValueError(f"資料被截斷（要 {e['comp_size']}，只有 {len(comp)}）")
            pcm = fab_decompress(comp, e["uncomp_size"])
            if len(pcm) != e["uncomp_size"]:
                raise ValueError(f"解開後大小不符（要 {e['uncomp_size']}，得 {len(pcm)}）")
            rate = e["frequency"] or 11025
            path = os.path.join(out, f"sfx-{i:03d}.wav")
            with open(path, "wb") as f:
                f.write(wav_header(len(pcm), rate))
                f.write(pcm)
            sizes.append((i, len(pcm), rate))
            ok += 1
        except Exception as ex:
            print(f"  ✗ #{i}: {ex}")
            fail += 1

    print(f"\n解出 {ok} 筆，失敗 {fail} 筆 → {out}")
    if sizes:
        sizes.sort(key=lambda t: -t[1])
        print("最長的幾筆（index, 位元組, 取樣率）：")
        for i, n, r in sizes[:8]:
            print(f"  #{i:3d}  {n:>8,} bytes  {r} Hz  約 {n / r:.2f} 秒")


if __name__ == "__main__":
    main()
