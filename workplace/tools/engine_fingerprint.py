#!/usr/bin/env python3
"""算引擎指紋：sha256(所有 engines/mads/**/*.cpp,*.h 依路徑排序後串接) 取前 12 碼。

為什麼需要這個：包驗收如果只比中文資料的 md5，對「只改引擎、資料沒動」的情況是
完全的盲區 —— 六個包資料全對，其中兩個裝的卻是修正前的引擎，而檢查全綠。
指紋讓「這個包裡的引擎是哪一版」變成可驗證的事實。

三平台的引擎都由同一份 patch 套出來，所以指紋必須相同；不同就是有一個平台漏套或套錯。

用法：
    engine_fingerprint.py <scummvm 樹>            印出指紋
    engine_fingerprint.py <樹> --write <輸出檔>   同時寫成 ENGINE.txt
    engine_fingerprint.py <樹> --expect <指紋>    比對，不符則非零退出
"""
import hashlib
import os
import sys


def fingerprint(tree):
    root = os.path.join(tree, "engines", "mads")
    if not os.path.isdir(root):
        sys.exit(f"### {root} 不存在 ###")
    paths = []
    for d, _dirs, files in os.walk(root):
        for fn in files:
            if fn.endswith((".cpp", ".h")):
                full = os.path.join(d, fn)
                paths.append((os.path.relpath(full, root).replace(os.sep, "/"), full))
    paths.sort()
    h = hashlib.sha256()
    for _rel, full in paths:
        with open(full, "rb") as f:
            h.update(f.read())
    return h.hexdigest()[:12], len(paths)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    tree = sys.argv[1]
    fp, n = fingerprint(tree)
    print(f"引擎指紋: {fp}  ({n} 個 .cpp/.h)")

    if "--expect" in sys.argv:
        want = sys.argv[sys.argv.index("--expect") + 1]
        if fp != want:
            sys.exit(f"### 指紋不符：預期 {want}，實得 {fp} ###")
        print(f"✓ 與預期一致（{want}）")

    if "--write" in sys.argv:
        out = sys.argv[sys.argv.index("--write") + 1]
        os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
        with open(out, "w", encoding="utf-8") as f:
            f.write(
                "《錯體奇航》繁體中文化 — 引擎指紋\n"
                "\n"
                "演算法: sha256(engines/mads/**/*.cpp 與 *.h 依路徑排序後內容串接) 取前 12 碼\n"
                f"指紋: {fp}\n"
                f"檔案數: {n}\n"
                "基準: ScummVM v2.8.0 + patches/rex-cht-engine.patch\n"
                "\n"
                "用途: 比對包裡的引擎版本。只比中文資料 md5 的驗收，對「只改引擎」是盲區，\n"
                "      所以另外對引擎原始碼本身做指紋。三平台由同一份 patch 套出，指紋應相同。\n"
            )
        print(f"寫入 {out}")


if __name__ == "__main__":
    main()
