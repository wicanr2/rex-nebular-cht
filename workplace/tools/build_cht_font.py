#!/usr/bin/env python3
"""從譯文取字集 → 倚天點陣字抽字模 → 烘成 rex_big5.fnt。

字型格式（自訂，簡單到不會出錯）：
  magic  "RXCF"          4 bytes
  width  uint8           字模寬（16）
  height uint8           字模高（15）
  count  uint16 LE       字數
  codes  count × uint16 LE   Big5 碼，**已排序**（引擎端二分搜尋）
  glyphs count × stride      stride = ((width+7)//8) * height，MSB-first、由上而下

為什麼只烘用到的字：字集由譯文決定，字型大小就跟著譯文走（幾千字約 100KB），
不必帶整套 13094 字。代價是改譯文要重烘——這正好逼著「譯文與字型一起出版」。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eten import EtenFont, eten_slot  # noqa: E402

MAGIC = b"RXCF"


def collect_chars(paths):
    """從 TSV 的第三欄（譯文）收集所有非 ASCII 字元。"""
    chars = set()
    for p in paths:
        with open(p, encoding="utf-8") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) < 3:
                    continue
                for ch in parts[2]:
                    if ord(ch) > 0x7F:
                        chars.add(ch)
    return chars


def main():
    if len(sys.argv) < 4:
        print("用法: build_cht_font.py <out.fnt> <std> <spc> <譯文tsv...>")
        return 2
    out_path, std_path, spc_path = sys.argv[1], sys.argv[2], sys.argv[3]
    tsvs = sys.argv[4:]

    font = EtenFont(std_path, spc_path, 16, 15)
    chars = collect_chars(tsvs)
    print("譯文用到的非 ASCII 字元: %d 個" % len(chars))

    entries = []
    missing = []
    for ch in sorted(chars):
        try:
            b = ch.encode("cp950")
        except UnicodeEncodeError:
            missing.append((ch, "非 Big5 字"))
            continue
        if len(b) != 2:
            missing.append((ch, "非雙位元組"))
            continue
        code = (b[0] << 8) | b[1]
        slot = eten_slot(b[0], b[1])
        if slot is None:
            missing.append((ch, "倚天無此碼位 %04X" % code))
            continue
        g = font.glyph_by_slot(*slot)
        if g is None:
            missing.append((ch, "倚天字模越界 %04X" % code))
            continue
        entries.append((code, g))

    entries.sort(key=lambda e: e[0])

    with open(out_path, "wb") as f:
        f.write(MAGIC)
        f.write(bytes([font.w, font.h]))
        f.write(len(entries).to_bytes(2, "little"))
        for code, _ in entries:
            f.write(code.to_bytes(2, "little"))
        for _, g in entries:
            f.write(g)

    size = os.path.getsize(out_path)
    print("烘出 %d 字 → %s (%d bytes, stride=%d)" % (len(entries), out_path, size, font.stride))

    if missing:
        print("\n[警告] %d 個字沒烘進去（畫面上會變空白，必須補 corrections）:" % len(missing))
        for ch, why in missing[:30]:
            print("   %r  %s" % (ch, why))
    return 0


if __name__ == "__main__":
    sys.exit(main())
