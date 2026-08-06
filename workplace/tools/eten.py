#!/usr/bin/env python3
"""倚天中文系統(ETEN)原生點陣字讀取。

為什麼不用 TTF：1990 年的 DOS 中文長什麼樣，倚天就長什麼樣。TTF 縮到 15–24px
筆劃比例不對、複雜字糊成一團；倚天是為該尺寸手工調過的點陣字。

來源檔（裸格式，每列 (W+7)//8 bytes、MSB-first、由上而下）：
  STDFONT.15  16×15 漢字 13094 字，30 B/字
  SPCFONT.15  16×15 全形標點 408 字，30 B/字   ← 漏帶會讓所有標點掉 fallback

索引是「Big5 分區」不是線性（符號區／常用區／次常用區三段），見 eten_slot()。
驗收 oracle：STDFONT.15 的 idx=0 必須是「一」；「中」(A4A4)、「猴」(B555)
dump 成 ASCII art 要可辨識。過不了就是索引錯，先別往下做。
"""
import sys


def raw(hi, lo):
    return (hi - 0xA1) * 157 + ((lo - 0x40) if lo < 0x7F else (lo - 0x62))


LAST_SPC = raw(0xA3, 0xBF)      # 符號區尾 = 407
BASE_A440 = raw(0xA4, 0x40)     # 漢字常用區起點
LAST_COMMON = raw(0xC6, 0x7E)   # 常用字尾
BASE_C940 = raw(0xC9, 0x40)     # 次常用起點
N_COMMON = 5401


def eten_slot(hi, lo):
    """回傳 ('spc'|'std', idx)；倚天沒有的碼位回 None。"""
    r = raw(hi, lo)
    if r < 0:
        return None
    if r <= LAST_SPC:
        return ("spc", r)
    if r < BASE_A440:
        return None                       # A3C0–A3FE 控制碼區
    if r <= LAST_COMMON:
        return ("std", r - BASE_A440)
    if r < BASE_C940:
        return None                       # C6A1–C8FE 造字區
    return ("std", N_COMMON + (r - BASE_C940))


class EtenFont:
    def __init__(self, std_path, spc_path, width=16, height=15):
        self.w = width
        self.h = height
        self.bpr = (width + 7) // 8
        self.stride = self.bpr * height
        with open(std_path, "rb") as f:
            self.std = f.read()
        with open(spc_path, "rb") as f:
            self.spc = f.read()

    def glyph_by_slot(self, kind, idx):
        buf = self.std if kind == "std" else self.spc
        off = idx * self.stride
        if off + self.stride > len(buf):
            return None
        return buf[off:off + self.stride]

    def glyph(self, big5_code):
        """big5_code 為 0xA4A4 這種 16-bit 值。"""
        slot = eten_slot(big5_code >> 8, big5_code & 0xFF)
        if slot is None:
            return None
        return self.glyph_by_slot(*slot)

    def embolden(self, g):
        """筆劃水平膨脹 1px。15 點倚天只有偏細明體，疊在深色面板上對比不足。"""
        out = bytearray(g)
        for row in range(self.h):
            base = row * self.bpr
            for col in range(self.w - 1, 0, -1):
                if g[base + ((col - 1) >> 3)] & (0x80 >> ((col - 1) & 7)):
                    out[base + (col >> 3)] |= (0x80 >> (col & 7))
        return bytes(out)

    def ascii_art(self, g):
        lines = []
        for row in range(self.h):
            line = ""
            for col in range(self.w):
                b = g[row * self.bpr + (col >> 3)]
                line += "#" if (b & (0x80 >> (col & 7))) else "."
            lines.append(line)
        return "\n".join(lines)


def main():
    std = sys.argv[1] if len(sys.argv) > 1 else "font-src/STDFONT.15"
    spc = sys.argv[2] if len(sys.argv) > 2 else "font-src/SPCFONT.15"
    f = EtenFont(std, spc)

    print("字庫大小: STDFONT %d bytes (%d 字) / SPCFONT %d bytes (%d 字)" %
          (len(f.std), len(f.std) // f.stride, len(f.spc), len(f.spc) // f.stride))

    ok = True
    # oracle 1: std idx=0 必須是「一」
    g = f.glyph_by_slot("std", 0)
    art = f.ascii_art(g)
    filled_rows = [i for i, ln in enumerate(art.split("\n")) if "#" in ln]
    one_ok = len(filled_rows) <= 3      # 「一」只有中間一兩列有筆劃
    print("\n[oracle 1] std idx=0 應為「一」 →", "PASS" if one_ok else "FAIL")
    print(art)
    ok &= one_ok

    # oracle 2/3: 「中」A4A4、「猴」B555 要可辨識
    for name, code in (("中", 0xA4A4), ("猴", 0xB555)):
        g = f.glyph(code)
        if g is None:
            print("\n[oracle] %s (%04X) 取不到字模 → FAIL" % (name, code))
            ok = False
            continue
        art = f.ascii_art(g)
        density = sum(ln.count("#") for ln in art.split("\n"))
        print("\n[oracle] %s (%04X) 筆劃點數 %d" % (name, code, density))
        print(art)
        ok &= (density > 20)

    # oracle 4: 全形標點在 SPCFONT 裡
    for name, code in (("，", 0xA141), ("。", 0xA143), ("「", 0xA16D)):
        slot = eten_slot(code >> 8, code & 0xFF)
        print("[oracle] %s (%04X) → %s" % (name, code, slot))
        ok &= (slot is not None and slot[0] == "spc")

    print("\n整體:", "PASS — 索引正確，可以烘字" if ok else "FAIL — 索引錯了，先別往下做")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
