#!/usr/bin/env python3
"""抽出《錯體奇航》全部可翻譯文字。

來源與出處（ScummVM 2.8.0）：
  QUOTES.DAT   null-terminated 字串陣列        game.cpp:346  Game::loadQuotes()
  VOCAB.DAT    null-terminated 字串陣列        scene.cpp:257 Scene::loadVocabStrings()
  MESSAGES.DAT 索引表 + FAB 壓縮區塊            game.cpp:368  Game::getMessage()
  *.TXR        TextView 文字（片尾／引言畫面）  menu_views.cpp TextView
  HOGANUS.DAT  防拷題庫                        dialogs_nebular.h:74

輸出 TSV：id <TAB> 原文（\n 以 \\n 逃脫）
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mads_res import HagArchive, fab_decompress, is_madspack, madspack_items, u16, u32  # noqa: E402


def split_cstrings(data):
    """切 null-terminated 字串。回傳 list[bytes]。"""
    out = []
    cur = bytearray()
    for b in data:
        if b == 0:
            out.append(bytes(cur))
            cur = bytearray()
        else:
            cur.append(b)
    if cur:
        out.append(bytes(cur))
    return out


def load_quotes(arc):
    """完全比照 loadQuotes()：逐 byte 累積，遇 \\0 或 eos 就斷。"""
    data = arc.read("QUOTES.DAT")
    quotes = []
    cur = bytearray()
    for i, b in enumerate(data):
        if b != 0:
            cur.append(b)
        last = (i == len(data) - 1)
        if b == 0 or last:
            quotes.append(bytes(cur))
            cur = bytearray()
    return quotes


def load_vocab(arc):
    data = arc.read("VOCAB.DAT")
    return split_cstrings(data)


def load_messages(arc):
    """回傳 [(itemId, [行, 行, ...]), ...]，比照 Game::getMessage()。"""
    data = arc.read("MESSAGES.DAT")
    count = u16(data, 0)
    index = []
    for i in range(count):
        off = 2 + i * 10
        item_id = u32(data, off)
        offset = u32(data, off + 4)
        size = u16(data, off + 8)
        index.append((item_id, offset, size))

    out = []
    for i, (item_id, offset, size) in enumerate(index):
        if i == count - 1:
            size_in = len(data) - offset
        else:
            size_in = index[i + 1][1] - offset
        raw = data[offset:offset + size_in]
        plain = fab_decompress(raw, size)
        out.append((item_id, split_cstrings(plain)))
    return out


def load_txr(arc, name):
    data = arc.read(name)
    if is_madspack(data):
        data = madspack_items(data)[0][2]
    return data


def esc(b):
    s = b.decode("latin-1")
    return s.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")


def main():
    game = sys.argv[1] if len(sys.argv) > 1 else "game"
    outdir = sys.argv[2] if len(sys.argv) > 2 else "out/text"
    os.makedirs(outdir, exist_ok=True)
    arc = HagArchive(game)

    quotes = load_quotes(arc)
    with open(os.path.join(outdir, "quotes.tsv"), "w", encoding="utf-8") as f:
        for i, q in enumerate(quotes, 1):          # getQuote() 的 index 從 1 起
            f.write("%d\t%s\n" % (i, esc(q)))

    vocab = load_vocab(arc)
    with open(os.path.join(outdir, "vocab.tsv"), "w", encoding="utf-8") as f:
        for i, v in enumerate(vocab):
            f.write("%d\t%s\n" % (i, esc(v)))

    messages = load_messages(arc)
    msg_lines = 0
    with open(os.path.join(outdir, "messages.tsv"), "w", encoding="utf-8") as f:
        for item_id, lines in messages:
            for j, line in enumerate(lines):
                f.write("%d.%d\t%s\n" % (item_id, j, esc(line)))
                msg_lines += 1

    txr_names = sorted(n for _, n, _, _ in arc.list_all() if n.upper().endswith(".TXR"))
    txr_total = 0
    with open(os.path.join(outdir, "txr.tsv"), "w", encoding="utf-8") as f:
        for name in txr_names:
            data = load_txr(arc, name)
            for j, line in enumerate(data.split(b"\n")):
                line = line.rstrip(b"\r")
                f.write("%s.%d\t%s\n" % (name, j, esc(line)))
                txr_total += 1

    hoganus = arc.read("HOGANUS.DAT")
    with open(os.path.join(outdir, "hoganus.tsv"), "w", encoding="utf-8") as f:
        for i, s in enumerate(split_cstrings(hoganus)):
            f.write("%d\t%s\n" % (i, esc(s)))

    print("QUOTES.DAT    %5d 則" % len(quotes))
    print("VOCAB.DAT     %5d 則" % len(vocab))
    print("MESSAGES.DAT  %5d 組 / %d 行" % (len(messages), msg_lines))
    print("*.TXR         %5d 行 (%d 檔: %s)" % (txr_total, len(txr_names), ", ".join(txr_names)))
    print("HOGANUS.DAT   %5d 則" % len(split_cstrings(hoganus)))


if __name__ == "__main__":
    main()
