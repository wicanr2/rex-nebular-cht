#!/usr/bin/env python3
"""把抽出的文字整理成「可翻譯批次」。

設計決定（寫在這裡免得後人以為是隨手選的）：
1. MESSAGES 以「組」(item_id) 為翻譯單位，不是以行。原文的換行是為 320 寬英文字
   手動斷的，中文寬度不同必須重排；逐行翻譯還會讓 subagent 看不到上下文。
2. key 一律用「資源內的 index / id」，不用英文原文當 key —— 原文有大量重複
   （ON/OFF/STILL 各出現兩次），用內容當 key 會撞。
3. 控制碼 [titleN] [sentence] [nounN:it:them] 等一律原樣保留，位置與數量不得增減。

輸出：out/batches/<來源>-<批號>.tsv，欄位 = key <TAB> 原文 <TAB> （空的譯文欄）
"""
import os
import re
import sys

# 一批的「則」數。vocab 全是短詞可以塞多一點；messages 一則是一整段對白，取 130
# （LSL1 實測的甜蜜點：再多 subagent 會開始偷懶漏行）。
BATCH_SIZES = {"vocab": 300, "quotes": 130, "messages": 130, "txr": 130}
BATCH_SIZE = 130


def read_tsv(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            k, _, v = line.rstrip("\n").partition("\t")
            rows.append((k, v))
    return rows


def group_messages(rows):
    """messages.tsv 的 key 是 '<id>.<行號>' → 合併回組，行以 \\n 連接。"""
    groups = {}
    order = []
    for k, v in rows:
        gid = k.split(".")[0]
        if gid not in groups:
            groups[gid] = []
            order.append(gid)
        groups[gid].append(v)
    return [(gid, "\\n".join(groups[gid])) for gid in order]


def is_translatable(text):
    """純控制碼、純數字、空字串不送翻譯。"""
    t = text.strip()
    if not t:
        return False
    stripped = re.sub(r"\[[^\]]*\]", "", t).replace("\\n", " ").strip()
    if not stripped:
        return False
    if not re.search(r"[A-Za-z]{2}", stripped):
        return False
    return True


def write_batches(name, items, outdir):
    todo = [(k, v) for k, v in items if is_translatable(v)]
    skipped = len(items) - len(todo)
    size = BATCH_SIZES.get(name, BATCH_SIZE)
    n = 0
    for i in range(0, len(todo), size):
        n += 1
        path = os.path.join(outdir, "%s-%02d.tsv" % (name, n))
        with open(path, "w", encoding="utf-8") as f:
            for k, v in todo[i:i + size]:
                f.write("%s\t%s\t\n" % (k, v))
    print("%-10s %5d 則可譯 / 略過 %4d 則 → %d 批" % (name, len(todo), skipped, n))
    return n


def main():
    textdir = sys.argv[1] if len(sys.argv) > 1 else "out/text"
    outdir = sys.argv[2] if len(sys.argv) > 2 else "out/batches"
    os.makedirs(outdir, exist_ok=True)

    total = 0
    total += write_batches("vocab", read_tsv(os.path.join(textdir, "vocab.tsv")), outdir)
    total += write_batches("quotes", read_tsv(os.path.join(textdir, "quotes.tsv")), outdir)
    total += write_batches("messages", group_messages(read_tsv(os.path.join(textdir, "messages.tsv"))), outdir)
    total += write_batches("txr", read_tsv(os.path.join(textdir, "txr.tsv")), outdir)
    print("合計 %d 批" % total)


if __name__ == "__main__":
    main()
