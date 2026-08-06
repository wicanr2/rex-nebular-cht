#!/usr/bin/env python3
"""可逆性證明：抽出的字串重組回原始 bytes，必須完全相同（diff = 0）。"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mads_res import HagArchive, fab_decompress, u16, u32  # noqa: E402
from extract_text import load_quotes, load_vocab, split_cstrings  # noqa: E402


def check(name, orig, rebuilt):
    ok = orig == rebuilt
    print("%-14s %-6s 原始 %d bytes / 重組 %d bytes" %
          (name, "PASS" if ok else "FAIL", len(orig), len(rebuilt)))
    if not ok:
        for i in range(min(len(orig), len(rebuilt))):
            if orig[i] != rebuilt[i]:
                print("   首個差異 @%d: %02X vs %02X" % (i, orig[i], rebuilt[i]))
                break
    return ok


def main():
    arc = HagArchive(sys.argv[1] if len(sys.argv) > 1 else "game")
    allok = True

    orig = arc.read("QUOTES.DAT")
    allok &= check("QUOTES.DAT", orig, b"\0".join(load_quotes(arc)) + b"\0")

    orig = arc.read("VOCAB.DAT")
    allok &= check("VOCAB.DAT", orig, b"\0".join(load_vocab(arc)) + b"\0")

    # MESSAGES：逐組驗「解壓 → 切字串 → 重組」與解壓結果一致
    data = arc.read("MESSAGES.DAT")
    count = u16(data, 0)
    idx = [(u32(data, 2 + i * 10), u32(data, 6 + i * 10), u16(data, 10 + i * 10))
           for i in range(count)]
    bad = 0
    for i, (item_id, offset, size) in enumerate(idx):
        size_in = (len(data) - offset) if i == count - 1 else (idx[i + 1][1] - offset)
        plain = fab_decompress(data[offset:offset + size_in], size)
        if b"\0".join(split_cstrings(plain)) + b"\0" != plain:
            bad += 1
    print("%-14s %-6s %d/%d 組解壓後可完整重組" %
          ("MESSAGES.DAT", "PASS" if bad == 0 else "FAIL", count - bad, count))
    allok &= (bad == 0)

    print("\n整體:", "PASS — 解析可逆，可以動文字" if allok else "FAIL — 先修解析器")
    return 0 if allok else 1


if __name__ == "__main__":
    sys.exit(main())
