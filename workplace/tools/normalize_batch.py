#!/usr/bin/env python3
"""譯文正規化 + 譯名收斂（合併前的最後一手）。

做三件事：
1. 半形標點 → 全形。**但控制碼 `[...]` 內部一個字都不能動**
   （`[noun1:it:them]` 的冒號是引擎語法，改了整批失效）。
2. 不可編碼字元替換：`・`(U+30FB) / `·`(U+00B7) → `‧`(U+2027)。
   前者不在 cp950 裡，會讓整行在合併時被丟掉——而它正好常用在人名中點。
3. 譯名收斂：同一個英文詞被不同批次翻成不同中文時，統一成定案版本。

用法：normalize_batch.py <批次目錄> [--dry-run]
"""
import glob
import os
import re
import sys

TAG = re.compile(r"(\[[^\]]*\])")

PUNCT = {
    ",": "，", ";": "；", ":": "：", "!": "！", "?": "？",
    "(": "（", ")": "）",
}

# 人名中點統一用 U+2027「‧」（台灣標準寫法，cp950 = A145）。
# U+30FB「・」不在 cp950 裡，抄進譯文會讓整行在合併時被丟掉。
CHAR_FIX = {"・": "‧", "·": "‧"}

# 譯名收斂：{錯誤或分歧的寫法: 定案}
GLOSSARY_FIX = {
    "聚合膠": "強力膠",
    "強力膠泥": "強力膠",
    "肚臍星": "臍帶星",
    "史萊契醫生": "史萊奇醫師",
    "史萊許": "史萊奇",
    "變體者": "變體人",
    "小豬號": "油豬號",
}


def normalize_text(text):
    """只對控制碼以外的片段做標點正規化。"""
    out = []
    for part in TAG.split(text):
        if part.startswith("[") and part.endswith("]"):
            out.append(part)          # 控制碼原樣保留
            continue
        # 半形句號要小心：英文縮寫與 "..." 省略號都會用到，只轉「中文字後面的句號」
        part = re.sub(r"(?<=[一-鿿])\.(?![\.\d])", "。", part)
        for a, b in PUNCT.items():
            # 半形括號在譯文裡多半是中文用途，直接轉
            part = part.replace(a, b)
        for a, b in CHAR_FIX.items():
            part = part.replace(a, b)
        out.append(part)
    return "".join(out)


def main():
    batch_dir = sys.argv[1] if len(sys.argv) > 1 else "out/batches"
    dry = "--dry-run" in sys.argv

    total_punct = total_gloss = 0
    for path in sorted(glob.glob(os.path.join(batch_dir, "*.tsv"))):
        rows = []
        changed_punct = changed_gloss = 0
        with open(path, encoding="utf-8") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) < 3 or not parts[2]:
                    rows.append(parts)
                    continue

                orig = parts[2]
                text = normalize_text(orig)
                if text != orig:
                    changed_punct += 1

                before = text
                for a, b in GLOSSARY_FIX.items():
                    text = text.replace(a, b)
                if text != before:
                    changed_gloss += 1

                parts[2] = text
                rows.append(parts)

        if (changed_punct or changed_gloss) and not dry:
            with open(path, "w", encoding="utf-8") as f:
                f.write("\n".join("\t".join(r) for r in rows) + "\n")

        if changed_punct or changed_gloss:
            print("%-24s 標點 %3d 行 / 譯名 %2d 行" %
                  (os.path.basename(path), changed_punct, changed_gloss))
        total_punct += changed_punct
        total_gloss += changed_gloss

    print("\n合計：標點正規化 %d 行、譯名收斂 %d 行%s" %
          (total_punct, total_gloss, "（dry-run，未寫檔）" if dry else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
