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
    leak_scan.py <zip / tar.gz / 目錄> [...]
    leak_scan.py --git [repo]     掃 git **追蹤中**的檔案（公開 repo 的真正把關點）
    leak_scan.py --self-test
"""
import io
import os
import re
import sys
import tarfile
import zipfile

CATEGORIES = (
    ("遊戲資料", re.compile(
        r"(^|/)([^/]*\.(hag|res)$|(a|i|p|r|x)sound\.[0-9]{3}$|digital\.aga$)", re.I)),
    ("MT-32 ROM", re.compile(r"\.rom$", re.I)),
    ("手冊掃描", re.compile(r"\.pdf$", re.I)),
    # [雷] 這一類原本只列 wav|raw|mp4|ogg|mp3|flac，**漏了 mkv** —— 而遊玩錄影
    # 正是 .mkv（x11grab + PulseAudio 錄出來的容器）。於是四個含原版配樂的錄影檔
    # 進了公開 repo，掃描照樣全綠。副檔名黑名單的通病：漏一個就是一個洞，
    # 而洞的形狀跟「通過」完全一樣。
    ("原版音訊/影片", re.compile(
        r"\.(wav|raw|mp4|mkv|mov|avi|webm|ogg|ogv|mp3|flac|m4a|aac)$", re.I)),
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


def git_tracked(repo="."):
    """git 目前**追蹤中**的檔案清單。

    [HARD] 這跟掃工作目錄、跟 `git check-ignore` 都不是同一件事：

      - 掃工作目錄會撈到一堆 gitignore 掉的素材（font-src、scummvm-src），
        全是紅字，看久了就當雜訊，真的洩漏反而混在裡面。
      - `git check-ignore` 只回答「**新**檔會不會被忽略」。**.gitignore 對已追蹤的
        檔案完全無效** —— 先 commit 再補 ignore，檔案會安安靜靜留在版控裡，
        而 check-ignore 的正對照照樣通過。這個專案就是這樣讓四個遊玩錄影
        （約 96 MB，含原版配樂）留在公開 repo 裡的。

    唯一能回答「公開 repo 裡現在有什麼」的，是這份清單。
    """
    import subprocess
    out = subprocess.run(["git", "-C", repo, "ls-files"],
                         capture_output=True, text=True, check=True)
    return out.stdout.splitlines()


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
    # macOS 交付是 .tar.gz 與 .dmg —— 原本只認 zip 與目錄，於是**三平台裡就
    # macOS 那包從來沒被掃過**，而指令跑起來的樣子是「### 不認得的目標 ###」，
    # 混在一堆 ✓ 中間很容易被當成用法寫錯而不是覆蓋缺口。
    if tarfile.is_tarfile(path):
        with tarfile.open(path) as t:
            return [m.name for m in t.getmembers() if m.isfile()]
    sys.exit(f"### 不認得的目標：{path}（要 zip / tar.gz / 目錄）###\n"
             f"###   .dmg 請先掛載或解開再掃 ###")


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
        z.writestr("out/gp-sync/raw.mkv", b"x")        # 原版影片（漏過一次的那個副檔名）
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
    if sys.argv[1] == "--git":
        repo = sys.argv[2] if len(sys.argv) > 2 else "."
        names = git_tracked(repo)
        ok = report(f"git 追蹤中的 {len(names)} 個檔（{os.path.abspath(repo)}）",
                    scan(names))
        sys.exit(0 if ok else 1)
    ok = True
    for path in sys.argv[1:]:
        ok &= report(path, scan(names_of(path)))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
