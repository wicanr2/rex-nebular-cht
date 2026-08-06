#!/usr/bin/env python3
"""把翻好的批次合併成引擎讀的 rex_cht.tsv。

key 命名對應引擎端的查表（engines/mads/cht.cpp）：
  vocab-*.tsv   → vocab:<陣列索引>    Scene::loadVocabStrings()
  quotes-*.tsv  → quote:<1 起算索引>  Game::loadQuotes()
  messages-*.tsv→ msg:<message id>    Game::getMessage()
  txr-*.tsv     → txr:<資源名>.<行號>  TextView::processLines()

只輸出「有譯文」的行。沒譯到的自動留英文，不會變成空白畫面。
"""
import glob
import os
import sys

PREFIX = {"vocab": "vocab", "quotes": "quote", "messages": "msg", "txr": "txr"}


def main():
    batch_dir = sys.argv[1] if len(sys.argv) > 1 else "out/batches"
    out_path = sys.argv[2] if len(sys.argv) > 2 else "out/rex_cht.tsv"

    rows = []
    stats = {}
    for path in sorted(glob.glob(os.path.join(batch_dir, "*.tsv"))):
        base = os.path.basename(path).rsplit("-", 1)[0]
        prefix = PREFIX.get(base)
        if prefix is None:
            continue
        n = 0
        with open(path, encoding="utf-8") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) < 3 or not parts[2].strip():
                    continue
                rows.append(("%s:%s" % (prefix, parts[0]), parts[2], os.path.basename(path)))
                n += 1
        stats[base] = stats.get(base, 0) + n

    # 逐行檢查可編碼性：不能編的要指出「哪個 key、哪個字」，
    # 不要讓 codec 直接拋 traceback（那只給得出 byte offset，查起來很痛苦）
    bad = []
    good = []
    for key, text, src in rows:
        try:
            text.encode("cp950")
        except UnicodeEncodeError:
            for ch in text:
                if ord(ch) > 0x7F:
                    try:
                        ch.encode("cp950")
                    except UnicodeEncodeError:
                        bad.append((src, key, ch))
            continue
        good.append("%s\t%s" % (key, text))

    with open(out_path, "w", encoding="cp950", errors="strict") as f:
        f.write("\n".join(good) + "\n")

    for k in sorted(stats):
        print("%-10s %5d 筆" % (k, stats[k]))
    print("合計 %d 筆 → %s (%d bytes, cp950 編碼)" %
          (len(good), out_path, os.path.getsize(out_path)))
    if bad:
        print("\n[警告] %d 個字不能編成 cp950，該行已跳過（畫面會留英文）:" % len(bad))
        for src, key, ch in bad[:20]:
            print("   %-18s %-14s %r U+%04X" % (src, key, ch, ord(ch)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
