#!/usr/bin/env python3
"""驗 Windows 交付包的六條編碼規則。

每一條在 Linux 上都測不出來，所以只能在打包階段驗。

[HARD] 這支自己帶正對照（--self-test）：造一個六條全違反的 zip 餵進同一套檢查，
       確認每條都叫得出來。「沒有紅字」有兩種可能 —— 包是好的，或檢查自己壞了。
       把正對照做成子指令而不是一次性的手工驗證，是為了讓它不會被忘記。

用法：
    check_windows_zip.py <zip>        驗一個包
    check_windows_zip.py --self-test  驗這支檢查本身
"""
import io
import os
import struct
import sys
import tempfile
import zipfile

RULES = (
    "1 檔名純 ASCII 且帶 UTF-8 旗標",
    "2 .bat 換行為 CRLF",
    "3 .bat 內容純 ASCII",
    "4 .bat 有 errorlevel 判斷與 pause",
    "5 README 為 UTF-8 with BOM 且 CRLF",
    "6 附靜態 scummvm.ini 且鎖 gui_language=en",
)


def check(zf):
    """回傳 {規則編號: [違規訊息…]}；空 dict 代表全過。"""
    bad = {}

    def fail(rule, msg):
        bad.setdefault(rule, []).append(msg)

    names = zf.namelist()

    # 規則 1
    # [雷] zipfile 回報的 flag_bits 來自 central directory。zip 的每個檔案還有一份
    # local file header，那裡也有 flag —— 有些工具只設其中一處，而解壓工具讀哪一處
    # 各家不同。兩處都要驗。
    #
    # [雷] 定位 local header 要用 central directory 記錄的 header_offset，
    # 不要暴力搜尋 PK\x03\x04：themes/*.zip 與 fonts.dat 本身就是 zip，
    # 存進外層後內部仍保留那個特徵，暴力搜尋會掃到巢狀內容並誤報一堆 OFF。
    zip_raw = None          # 整個 zip 的 bytes；下面規則 2/5 的 raw 是「單一檔案內容」，別混用
    if getattr(zf, "filename", None):
        try:
            with open(zf.filename, "rb") as f:
                zip_raw = f.read()
        except OSError:
            zip_raw = None

    for i in zf.infolist():
        if any(ord(c) > 127 for c in i.filename):
            fail(1, f"檔名含非 ASCII：{i.filename!r}")
        if not (i.flag_bits & 0x800):
            fail(1, f"central directory 沒有 UTF-8 旗標：{i.filename}")
        if zip_raw is not None:
            lo = i.header_offset
            if zip_raw[lo:lo + 4] != b"PK\x03\x04":
                fail(1, f"local header 位置不對：{i.filename}")
            else:
                lfh_flag = struct.unpack_from("<H", zip_raw, lo + 6)[0]
                if not (lfh_flag & 0x800):
                    fail(1, f"local file header 沒有 UTF-8 旗標：{i.filename}")

    # 規則 2/3/4
    bats = [n for n in names if n.lower().endswith(".bat")]
    if not bats:
        fail(4, "包內沒有 .bat 啟動器")
    for n in bats:
        raw = zf.read(n)
        if raw.count(b"\r\n") != raw.count(b"\n"):
            fail(2, f"{n} 有 LF-only 行")
        try:
            text = raw.decode("ascii")
        except UnicodeDecodeError:
            fail(3, f"{n} 含非 ASCII 位元組（中文提示要放 README，不要放 .bat）")
            text = raw.decode("cp950", errors="replace")
        low = text.lower()
        if "errorlevel" not in low:
            fail(4, f"{n} 沒有 if errorlevel 判斷，失敗時玩家看不到原因")
        if "pause" not in low:
            fail(4, f"{n} 沒有 pause，視窗會一閃就關掉")

    # 規則 5
    readmes = [n for n in names if n.lower().endswith(".txt") and "readme" in n.lower()]
    if not readmes:
        fail(5, "包內沒有 README")
    for n in readmes:
        raw = zf.read(n)
        if raw[:3] != b"\xef\xbb\xbf":
            fail(5, f"{n} 缺 UTF-8 BOM（舊記事本會當 ANSI 解讀 → 中文全亂）")
        if raw.count(b"\r\n") != raw.count(b"\n"):
            fail(5, f"{n} 有 LF-only 行（舊記事本會擠成一行）")

    # 規則 6
    inis = [n for n in names if n.lower().endswith(".ini")]
    if not inis:
        fail(6, "包內沒有 scummvm.ini（設定會落到玩家全域設定）")
    for n in inis:
        text = zf.read(n).decode("utf-8", errors="replace")
        if "gui_language=en" not in text.replace(" ", ""):
            fail(6, f"{n} 沒有鎖 gui_language=en")

    return bad


def report(bad, label):
    print(f"=== {label} ===")
    for idx, rule in enumerate(RULES, 1):
        if idx in bad:
            print(f"  ✗ 規則 {rule}")
            for m in bad[idx]:
                print(f"      {m}")
        else:
            print(f"  ✓ 規則 {rule}")
    return not bad


def build_broken_zip():
    """造一個六條全違反的包，給正對照用。"""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        # 違反 1：非 ASCII 檔名 + 不設 UTF-8 旗標
        zi = zipfile.ZipInfo("啟動遊戲.bat")
        zi.flag_bits &= ~0x800
        # 違反 2（LF-only）、3（含中文）、4（沒有 errorlevel / pause）
        z.writestr(zi, "@echo off\necho 開始遊戲\nscummvm.exe\n".encode("cp950"))
        # 違反 5：沒有 BOM + LF-only
        z.writestr("README-CHT.txt", "說明\n".encode("utf-8"))
        # 違反 6：ini 沒有鎖 gui_language
        z.writestr("scummvm.ini", "[scummvm]\nfullscreen=true\n")
    buf.seek(0)
    return buf


def build_lfh_only_broken():
    """造一個 central directory 有 UTF-8 旗標、local file header 卻沒有的 zip。

    真實世界會出現這種檔（某些打包工具只設一處），而只驗 zipfile.flag_bits
    的檢查會完全放行 —— 因為那個值讀的是 central directory。
    """
    fd, path = tempfile.mkstemp(suffix=".zip")
    os.close(fd)
    with zipfile.ZipFile(path, "w") as z:
        zi = zipfile.ZipInfo("PLAY-X.bat", date_time=(2026, 8, 7, 0, 0, 0))
        zi.flag_bits |= 0x800
        z.writestr(zi, b"@echo off\r\nerrorlevel\r\npause\r\n")
        z.writestr("README-CHT.txt", b"\xef\xbb\xbfx\r\n")
        z.writestr("scummvm.ini", b"[scummvm]\r\ngui_language=en\r\n")
    raw = bytearray(open(path, "rb").read())
    with zipfile.ZipFile(path) as z:
        for i in z.infolist():                      # 只把 local header 的旗標清掉
            lo = i.header_offset
            flag = struct.unpack_from("<H", raw, lo + 6)[0]
            struct.pack_into("<H", raw, lo + 6, flag & ~0x800)
    open(path, "wb").write(bytes(raw))
    return path


def self_test():
    with zipfile.ZipFile(build_broken_zip()) as z:
        bad = check(z)
    print("=== 正對照：餵一個六條全違反的包，每條都該被抓到 ===")
    missed = [r for r in range(1, 7) if r not in bad]
    for idx, rule in enumerate(RULES, 1):
        mark = "✓ 抓到" if idx in bad else "✗ 沒抓到"
        print(f"  {mark}  規則 {rule}")
        for m in bad.get(idx, []):
            print(f"           {m}")
    if missed:
        print(f"\n### 檢查本身有洞：規則 {missed} 放行了必定違規的輸入 ###")
        return False
    print("\n六條都會叫。")

    # 額外一輪：central directory 有旗標、local file header 沒有。
    # 只讀 zipfile.flag_bits 的檢查會放行這種檔。
    print("\n=== 正對照 2：只有 central directory 開旗標的包 ===")
    path = build_lfh_only_broken()
    try:
        with zipfile.ZipFile(path) as z:
            bad2 = check(z)
        hit = [m for m in bad2.get(1, []) if "local file header" in m]
        if hit:
            print(f"  ✓ 抓到：{hit[0]}")
        else:
            print("  ✗ 沒抓到 —— 只驗 central directory 會放行這種檔")
            return False
    finally:
        os.unlink(path)

    print("\n兩輪正對照都通過 —— 這套檢查本身是有效的。")
    return True


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if sys.argv[1] == "--self-test":
        sys.exit(0 if self_test() else 1)
    path = sys.argv[1]
    with zipfile.ZipFile(path) as z:
        bad = check(z)
    sys.exit(0 if report(bad, path) else 1)


if __name__ == "__main__":
    main()
