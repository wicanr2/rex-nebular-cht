#!/usr/bin/env python3
"""掃交付包裡有沒有混進版權素材。

要擋的四類（CLAUDE.md §16）：
  1. 遊戲資料      *.hag / *.RES / asound.* / isound.* / psound.* / rsound.* / xsound.* / digital.aga
  2. MT-32 ROM     *.ROM
  3. 手冊掃描      *.pdf
  4. 原版音訊/影片 *.wav / *.raw / *.mp4 / *.ogg / *.mp3
  5. 第三方原始字庫 STDFONT.15 / SPCFONT.15 / STD.24M（倚天中文系統）

放行的：ScummVM 自己的 GPL 素材（themes/*.zip、fonts.dat、encoding.dat）、
自製的譯文碼表與點陣字型、自編的執行檔與 DLL。

[HARD] 自帶正對照（--self-test）：造一個「四類全中」的包餵進同一套規則，
       確認每類都叫得出來。沒有紅字有兩種可能 —— 包是乾淨的，或掃描自己壞了。

用法：
    leak_scan.py <zip 或目錄> [...]
    leak_scan.py --self-test
"""
import io
import os
import re
import sys
import zipfile

CATEGORIES = (
    ("遊戲資料", re.compile(
        r"(^|/)([^/]*\.(hag|res)$|(a|i|p|r|x)sound\.[0-9]{3}$|digital\.aga$)", re.I)),
    ("MT-32 ROM", re.compile(r"\.rom$", re.I)),
    ("手冊掃描", re.compile(r"\.pdf$", re.I)),
    ("原版音訊/影片", re.compile(r"\.(wav|raw|mp4|ogg|mp3|flac)$", re.I)),
    # 倚天中文系統的原始字庫是 1990s 商業軟體資產。烘出來只含譯文用到那 2394 字的
    # rex_big5.fnt 是衍生物，跟散布整份原始字庫是兩回事 —— 後者不進公開 repo。
    ("第三方原始字庫", re.compile(
        r"(^|/)(std|spc)font\.\d+$|(^|/)std\.\d+[a-z]$|\.(24[a-z]|1[56])$", re.I)),
)

# ScummVM 自己的 GPL 素材，長得像遊戲資料但不是
ALLOW = re.compile(r"(^|/)themes/[^/]+\.(zip|dat)$|(^|/)(fonts|encoding)\.dat$", re.I)


def scan(names):
    hits = {}
    for n in names:
        if ALLOW.search(n):
            continue
        for label, pat in CATEGORIES:
            if pat.search(n):
                hits.setdefault(label, []).append(n)
    return hits


def names_of(path):
    if os.path.isdir(path):
        out = []
        for d, _dirs, fs in os.walk(path):
            for fn in fs:
                out.append(os.path.relpath(os.path.join(d, fn), path).replace(os.sep, "/"))
        return out
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as z:
            return z.namelist()
    sys.exit(f"### 不認得的目標：{path}（要 zip 或目錄）###")


def report(path, hits):
    print(f"=== {path} ===")
    for label, _pat in CATEGORIES:
        if label in hits:
            print(f"  ✗ 混進{label}：")
            for n in hits[label]:
                print(f"      {n}")
        else:
            print(f"  ✓ 無{label}")
    return not hits


def self_test():
    print("=== 正對照：餵一個四類全中的包，每類都該被抓到 ===")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("game/global.hag", b"x")            # 遊戲資料
        z.writestr("game/asound.001", b"x")            # 遊戲資料（另一形態）
        z.writestr("MT32_CONTROL.ROM", b"x")           # ROM
        z.writestr("docs/manual.pdf", b"x")            # 手冊掃描
        z.writestr("promo/bgm.wav", b"x")              # 原版音訊
        z.writestr("font-src/STDFONT.15", b"x")        # 第三方原始字庫
        z.writestr("themes/scummmodern.zip", b"x")     # 放行項，不該被抓
        z.writestr("cht-data/rex_cht.tsv", b"x")       # 放行項
        z.writestr("cht-data/rex_big5.fnt", b"x")      # 放行項：只含用到的字，是衍生物
    buf.seek(0)
    with zipfile.ZipFile(buf) as z:
        hits = scan(z.namelist())

    ok = True
    for label, _pat in CATEGORIES:
        if label in hits:
            print(f"  ✓ 抓到 {label}：{hits[label]}")
        else:
            print(f"  ✗ 沒抓到 {label} —— 掃描有洞")
            ok = False
    # 反向：放行項不該被誤報
    flat = [n for v in hits.values() for n in v]
    for good in ("themes/scummmodern.zip", "cht-data/rex_cht.tsv", "cht-data/rex_big5.fnt"):
        if good in flat:
            print(f"  ✗ 誤報放行項：{good}")
            ok = False
        else:
            print(f"  ✓ 未誤報 {good}")
    print("\n" + ("四類都會叫、放行項不誤報 —— 這套掃描是有效的。" if ok else "### 掃描本身有洞 ###"))
    return ok


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if sys.argv[1] == "--self-test":
        sys.exit(0 if self_test() else 1)
    ok = True
    for path in sys.argv[1:]:
        ok &= report(path, scan(names_of(path)))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
