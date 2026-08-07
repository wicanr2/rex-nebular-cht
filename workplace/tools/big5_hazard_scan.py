#!/usr/bin/env python3
"""許功蓋風險掃描：把「引擎會比對哪些字元」跟「譯文裡有哪些字撞上它」交叉起來。

為什麼要有這支：前面三次都是**看到畫面壞掉才回頭找**，一次一型：
  ① strchr 逐 byte 掃          → menu_views.cpp
  ② hasSuffix("s") 判結尾      → dialogs_nebular.cpp
  ③ toUppercase 逐 byte 加減   → dialogs_nebular / action / user_interface
  ④ '[' / ']' 指令括號解析     → dialogs_nebular.cpp（460/4357 行踩中才發現）
每次都以為「這次總算掃乾淨了」。第 ④ 型是靠一張截圖上「這麼」後面一個半形怪
符號才發現的 —— 而它影響 10% 的譯文。等畫面出問題不是策略。

做法：
  1. 從引擎原始碼抓出所有「拿單一字元跟某個 byte 比對」的位置。
  2. 只留下字元值落在 Big5 trail byte 範圍的（那才可能被中文字的第二個
     位元組撞到）。ASCII 空白、換行、NUL 不在範圍內，自動排除，不用人腦判。
  3. 對每個危險字元，掃譯文算出實際會撞的字與行數 —— 有譯文佐證的才是真風險，
     沒有的列為潛在風險（換一批譯文就可能中）。
  4. 看那行程式碼附近有沒有 Big5 防護，沒有的標成 [未防護]。

用法：big5_hazard_scan.py <engines/mads 目錄> <譯文 tsv>
"""
import os
import re
import sys
from collections import defaultdict

# Big5：lead byte A1–F9，trail byte 40–7E 或 A1–FE。
# 只有 trail byte 落在 ASCII 可見範圍（0x40–0x7E）時才會被誤判成 ASCII 字元 ——
# 這正是「許功蓋」這個名字的由來（許 A5 78 / 功 A5 5C / 蓋 BB 5C）。
TRAIL_ASCII_LO, TRAIL_ASCII_HI = 0x40, 0x7E

# 比對單一字元的常見寫法。逐 byte 走字串時，這些都會踩在 trail byte 上。
PATTERNS = [
    (re.compile(r"[=!]=\s*'(\\?.)'"),            "字元比較"),
    (re.compile(r"strchr\s*\([^,]+,\s*'(\\?.)'"), "strchr"),
    (re.compile(r"hasSuffix\s*\(\"(\\?.)\"\)"),   "hasSuffix"),
    (re.compile(r"hasPrefix\s*\(\"(\\?.)\"\)"),   "hasPrefix"),
    (re.compile(r"findFirstOf\s*\('(\\?.)'"),     "findFirstOf"),
    (re.compile(r"findLastOf\s*\('(\\?.)'"),      "findLastOf"),
]

ESCAPES = {"\\n": 0x0A, "\\r": 0x0D, "\\t": 0x09, "\\0": 0x00,
           "\\\\": 0x5C, "\\'": 0x27, "\\\"": 0x22}

# 這行程式碼附近出現這些字樣，就當它已經處理過 Big5。
#
# [雷] 一開始把 "cht" / "Cht" / "CHT" 也算進來，結果正對照過不了 ——
# 我把 dialogs_nebular.cpp 的 Big5 防護整段拆掉，掃描器照樣說「✓ 沒問題」，
# 因為同一個函式裡 `const bool chtOn = _vm->_cht && ...` 這行還在 window 內。
# 「附近提到中文化」不等於「這個迴圈有跳過雙位元組字」。
# 只認真正做得到事的東西：lead byte 比較，或 ChtSupport 的 Big5 安全版函式。
GUARD_HINTS = ("0xA1", "0xa1", "big5To", "big5Str", "big5Ends",
               "big5Starts", "big5Capital", "big5MapAscii")
# [雷] 一開始設 12 行，結果 dialogs_nebular.cpp 同一個迴圈裡 '[' 判成已防護、
# 四行之後的 ']' 判成未防護 —— 防護寫在迴圈開頭，離 ']' 差了 13 行。
# 一個迴圈罩得住的範圍比 12 行大，設 30。
GUARD_WINDOW = 30


def load_allowlist(path):
    """{(檔案 basename, 字元): [(特徵字串, 理由), ...]}"""
    out = {}
    if not path or not os.path.exists(path):
        return out
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 4:
                continue
            fn, ch, needle, reason = parts[0], parts[1], parts[2], parts[3]
            out.setdefault((fn, ch), []).append((needle, reason))
    return out


def char_value(tok):
    if tok in ESCAPES:
        return ESCAPES[tok]
    if len(tok) == 1:
        return ord(tok)
    return None


def scan_engine(root):
    """回傳 [(檔案, 行號, 字元值, 寫法, 原始行, 有無防護), ...]"""
    out = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in sorted(filenames):
            if not fn.endswith((".cpp", ".h")):
                continue
            path = os.path.join(dirpath, fn)
            rel = os.path.relpath(path, root)
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                lines = f.read().split("\n")
            for i, line in enumerate(lines):
                code = line.split("//")[0]          # 去掉行註解，避免掃到說明文字
                for pat, kind in PATTERNS:
                    for m in pat.finditer(code):
                        v = char_value(m.group(1))
                        if v is None or not (TRAIL_ASCII_LO <= v <= TRAIL_ASCII_HI):
                            continue
                        lo = max(0, i - GUARD_WINDOW)
                        ctx = "\n".join(lines[lo:i + GUARD_WINDOW])
                        guarded = any(h in ctx for h in GUARD_HINTS)
                        out.append((rel, i + 1, v, kind, line.strip(), guarded))
    return out


def scan_translations(tsv_path):
    """回傳 {trail byte 值: {字(unicode): 出現行數}}"""
    hits = defaultdict(lambda: defaultdict(int))
    with open(tsv_path, "rb") as f:
        for raw in f.read().split(b"\n"):
            if not raw or raw.startswith(b"#"):
                continue
            parts = raw.split(b"\t", 1)
            if len(parts) < 2:
                continue
            v = parts[1]
            seen = set()
            i = 0
            while i < len(v):
                if v[i] >= 0xA1 and i + 1 < len(v):
                    tb = v[i + 1]
                    if TRAIL_ASCII_LO <= tb <= TRAIL_ASCII_HI:
                        ch = v[i:i + 2].decode("big5", "replace")
                        seen.add((tb, ch))
                    i += 2
                else:
                    i += 1
            for tb, ch in seen:
                hits[tb][ch] += 1
    return hits


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    engine_dir, tsv = sys.argv[1], sys.argv[2]
    allow_path = sys.argv[3] if len(sys.argv) > 3 else \
        os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     "big5_hazard_allowlist.tsv")

    sites = scan_engine(engine_dir)
    tr = scan_translations(tsv)
    allow = load_allowlist(allow_path)

    print(f"引擎掃描：{len(sites)} 處拿 Big5 trail byte 範圍內的字元做比較")
    print(f"譯文掃描：{len(tr)} 種 trail byte 實際出現在譯文裡")
    print(f"豁免清單：{sum(len(v) for v in allow.values())} 列\n")

    by_char = defaultdict(list)
    for rel, ln, v, kind, text, guarded in sites:
        by_char[v].append((rel, ln, kind, text, guarded))

    unguarded_real = []
    exempted = []
    for v in sorted(by_char):
        chars = tr.get(v, {})
        total = sum(chars.values())
        top = sorted(chars.items(), key=lambda kv: -kv[1])[:6]
        mark = "實際命中" if total else "潛在"
        head = f"'{chr(v)}' (0x{v:02X})  {mark}"
        if total:
            head += f"：譯文 {total} 行、{len(chars)} 個字　例：" + \
                    " ".join(f"{c}×{n}" for c, n in top)
        print(head)
        for rel, ln, kind, text, guarded in by_char[v]:
            reason = None
            for needle, why in allow.get((os.path.basename(rel), chr(v)), []):
                if needle in text:
                    reason = why
                    break
            if guarded:
                tag = "  ✓ 已防護"
            elif reason:
                tag = "  – 已豁免"
            else:
                tag = "  ✗ 未防護"
            print(f"    {tag}  {rel}:{ln}  [{kind}]  {text[:70]}")
            if reason:
                print(f"              理由：{reason}")
                exempted.append((rel, ln, chr(v)))
            elif not guarded and total:
                unguarded_real.append((rel, ln, chr(v), total))
        print()

    if unguarded_real:
        print("### 未防護且譯文實際會撞的位置 ###")
        for rel, ln, c, total in unguarded_real:
            print(f"  {rel}:{ln}  比對 '{c}'，譯文 {total} 行會撞")
        print("\n修法：逐 byte 迴圈開頭先判 lead byte（>= 0xA1）把整個雙位元組字搬走，")
        print("      或改用 ChtSupport 的 Big5 安全版函式。")
        print("      確定那個字串不可能是譯文，就加進 big5_hazard_allowlist.tsv 並寫理由。")
        return 1

    print(f"✓ 沒有「未防護 × 譯文實際會撞」的組合（{len(exempted)} 處由豁免清單放行）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
