#!/usr/bin/env python3
"""批次譯文驗收（合併前的最後一道防線）。

檢查項目（任何一項 FAIL 就退回那一批重做）：
  1. 行數與原始批次相同、順序未變
  2. 第一欄 key、第二欄英文原文與原始批次逐字相同（subagent 手抄會出錯）
  3. 控制碼 [xxx] 的「種類與數量」與原文一致（位置可因語序調整）
  4. 譯文可用 Big5 編碼（不可打的字會在畫面上變空白）
  5. 譯文非空（未翻的要能被點出來，不是靜靜漏掉）

用法：verify_batch.py <原始批次目錄> <已翻批次檔...>
原始批次由 prep_batches.py 重新產生到暫存目錄，用來當比對基準。
"""
import os
import re
import sys

TAG = re.compile(r"\[[^\]]*\]")


def read_rows(path):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            while len(parts) < 3:
                parts.append("")
            rows.append(parts[:3])
    return rows


def check(orig_path, done_path):
    orig = read_rows(orig_path)
    done = read_rows(done_path)
    name = os.path.basename(done_path)
    problems = []

    if len(orig) != len(done):
        problems.append("行數不符：原始 %d / 譯後 %d" % (len(orig), len(done)))
        return name, problems, 0

    translated = 0
    for i, (o, d) in enumerate(zip(orig, done), 1):
        if o[0] != d[0]:
            problems.append("第 %d 行 key 被改動：%r → %r" % (i, o[0], d[0]))
        if o[1] != d[1]:
            problems.append("第 %d 行英文原文被改動（key=%s）" % (i, o[0]))
        if not d[2].strip():
            problems.append("第 %d 行未翻譯（key=%s）：%s" % (i, o[0], o[1][:40]))
            continue
        translated += 1

        # 控制碼種類與數量
        ot = sorted(TAG.findall(o[1]))
        dt = sorted(TAG.findall(d[2]))
        if ot != dt:
            miss = [t for t in ot if t not in dt]
            extra = [t for t in dt if t not in ot]
            problems.append("第 %d 行控制碼不符（key=%s）少了 %s 多了 %s"
                            % (i, o[0], miss or "—", extra or "—"))

        # Big5 可編碼性
        for ch in d[2]:
            if ord(ch) < 0x80:
                continue
            try:
                ch.encode("cp950")
            except UnicodeEncodeError:
                problems.append("第 %d 行有非 Big5(cp950) 字 %r（key=%s）" % (i, ch, o[0]))

    return name, problems, translated


def main():
    orig_dir = sys.argv[1]
    files = sys.argv[2:]
    total_problems = 0
    for done in files:
        orig = os.path.join(orig_dir, os.path.basename(done))
        if not os.path.exists(orig):
            print("%-18s SKIP 找不到基準檔 %s" % (os.path.basename(done), orig))
            continue
        name, problems, translated = check(orig, done)
        status = "PASS" if not problems else "FAIL"
        print("%-18s %-4s 已譯 %d 行%s" %
              (name, status, translated, "" if not problems else "，%d 個問題" % len(problems)))
        for p in problems[:15]:
            print("    - %s" % p)
        if len(problems) > 15:
            print("    - …另有 %d 個問題" % (len(problems) - 15))
        total_problems += len(problems)

    print("\n整體:", "PASS — 可以合併" if total_problems == 0 else "FAIL — %d 個問題待修" % total_problems)
    return 0 if total_problems == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
