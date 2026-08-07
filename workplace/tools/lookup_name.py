#!/usr/bin/env python3
"""從既有譯文反查某個專有名詞已經怎麼翻，避免同一個角色出現兩三種寫法。

譯名表（docs/20-glossary.md）收的是「開工前就定案」的詞，但翻譯過程中一定會冒出
表上沒有的名字。要新增一批譯文（例如後來才發現的動畫內嵌訊息）時，正確做法是
先問「這個名字前面 4357 筆裡怎麼翻的」，而不是自己重新想一個。

用法：lookup_name.py <game 目錄> <譯文 tsv> <名字> [名字...]
"""
import os
import subprocess
import sys
import tempfile

PREFIX = [("messages.tsv", "msg"), ("quotes.tsv", "quote"), ("vocab.tsv", "vocab")]


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    game_dir, tsv_path = sys.argv[1], sys.argv[2]
    names = sys.argv[3:]

    here = os.path.dirname(os.path.abspath(__file__))
    tmp = tempfile.mkdtemp()
    subprocess.run(["python3", os.path.join(here, "extract_text.py"), game_dir, tmp],
                   capture_output=True, check=False)

    en = {}
    for fn, pre in PREFIX:
        path = os.path.join(tmp, fn)
        if not os.path.exists(path):
            continue
        with open(path, encoding="latin-1") as f:
            for line in f:
                line = line.rstrip("\n")
                if not line or line.startswith("#"):
                    continue
                k, _, v = line.partition("\t")
                en.setdefault(f"{pre}:{k.split('.')[0]}", []).append(v)

    zh = {}
    with open(tsv_path, "rb") as f:
        for raw in f.read().split(b"\n"):
            if not raw or raw.startswith(b"#"):
                continue
            k, _, v = raw.partition(b"\t")
            zh[k.decode("latin-1")] = v.decode("big5", "replace")

    for n in names:
        print(f"=== {n} ===")
        shown = 0
        for k, texts in en.items():
            if k not in zh:
                continue
            if not any(n in t for t in texts):
                continue
            joined = " ".join(texts)
            print(f"  [{k}]")
            print(f"    EN: {joined[:110]}")
            print(f"    ZH: {zh[k][:110]}")
            shown += 1
            if shown >= 3:
                break
        if shown == 0:
            print("  （既有譯文查無 —— 這是新名字，決定譯法後補進 docs/20-glossary.md）")
        print()


if __name__ == "__main__":
    main()
