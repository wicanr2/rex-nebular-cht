#!/usr/bin/env python3
"""抽 MADS 動畫檔（*.AA）裡內嵌的訊息文字 —— 文字的第六個來源。

原本的 extract_text.py 只抽 QUOTES / VOCAB / MESSAGES / TXR / HOGANUS 五個來源，
漏了這一個。症狀不是崩潰，是**開場動畫裡冒出一個英文字**（實測：太空船場景的
`WRIT` 浮在椅子上方），而且它不在任何一份抽出來的 tsv 裡 —— 用「grep 譯文表」
的方式怎麼查都查不到，因為根本沒抽進來。

格式出處 ScummVM 2.8.0 `engines/mads/animation.cpp`：
  - `Animation::load()` (L228~240)：`.AA` 是 MadsPack，chunk 0 是 header
    （`_messagesCount` 在 L33），**chunk 1 是 message 陣列**。
  - `AnimMessage::load()` (L74~96)：每筆固定 **96 bytes**，逐欄位累加算出來的：
        off  0  int16  soundId
        off  2  char   msg[64]      ← null-terminated，不足補 0
        off 66  skip 4
        off 70  int16  x
        off 72  int16  y
        off 74  uint16 flags
        off 76  byte   rgb1[3]
        off 79  byte   rgb2[3]
        off 82  skip 2 (kernelMsgIndex 佔位)
        off 84  skip 6
        off 90  uint16 startFrame
        off 92  uint16 endFrame
        off 94  skip 2                → 共 96

    [雷] 這個長度不能目測。第一次寫成 100，結果**每個檔案的第一則訊息都正確**、
    第二則之後整個歪掉（座標變成 16384/16191、startFrame 變 65535）。
    只看前幾行輸出會以為工具是對的 —— 要看到「同一檔第二則」才會發現。
  - 繪製在 L569 `scene._kernelMessages.add(..., me._msg)`。

用法：extract_anim.py <game 目錄> <輸出 tsv>
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mads_res import HagArchive, is_madspack, madspack_items, u16  # noqa: E402

MSG_RECSIZE = 96


def parse_messages(data):
    """回傳 [(msg, x, y, startFrame, endFrame), ...]。"""
    if not is_madspack(data):
        return []
    items = madspack_items(data)   # [(type, priority, bytes), ...]
    if len(items) < 2:
        return []

    header = items[0][2]
    if len(header) < 8:
        return []
    # AAHeader::load() (animation.cpp:28) 依序讀 spriteSetsCount / miscEntriesCount /
    # frameEntriesCount / messagesCount，都是 uint16 → messagesCount 在 offset 6。
    count = u16(header, 6)
    if count == 0:
        return []

    chunk = items[1][2]

    # [HARD] round-trip 式的格式證明：chunk 的長度必須剛好是 count × 96。
    # 這比「抽出來的字看起來像話」強得多 —— record size 只要差一個 byte，
    # 第一筆仍會完全正確（第一版寫 100 就是這樣騙過我的），但長度對不上。
    # 對 50 個檔各驗一次，等於 50 個獨立樣本都同意 96 這個數字。
    if len(chunk) != count * MSG_RECSIZE:
        raise ValueError(
            f"chunk 長度 {len(chunk)} != {count} × {MSG_RECSIZE}"
            f"（差 {len(chunk) - count * MSG_RECSIZE}）—— record size 算錯了")

    out = []
    for i in range(count):
        off = i * MSG_RECSIZE
        rec = chunk[off:off + MSG_RECSIZE]
        raw = rec[2:2 + 64]
        msg = raw.split(b"\x00")[0].decode("latin-1")
        x = int.from_bytes(rec[70:72], "little", signed=True)
        y = int.from_bytes(rec[72:74], "little", signed=True)
        sf = u16(rec, 90)
        ef = u16(rec, 92)
        out.append((msg, x, y, sf, ef))
    return out


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    game_dir, out_path = sys.argv[1], sys.argv[2]

    arc = HagArchive(game_dir)
    # list_all() 回的是 (hag, name, offset, size)
    names = sorted({e[1] for e in arc.list_all() if e[1].upper().endswith(".AA")})

    rows = []
    scanned = 0
    for name in names:
        data = arc.read(name)
        if data is None:
            print(f"  ! {name} 讀不到")
            continue
        scanned += 1
        for msg, x, y, sf, ef in parse_messages(data):
            if msg.strip():
                rows.append((name, msg, x, y, sf, ef))

    with open(out_path, "w", encoding="utf-8") as f:
        f.write("# anim\tmsg\tx\ty\tstartFrame\tendFrame\n")
        for r in rows:
            f.write("\t".join(str(v) for v in r) + "\n")

    print(f"*.AA           {scanned} 檔 / {len(rows)} 則訊息")

    # [HARD] 正對照：這支工具的價值在「抓到 extract_text.py 漏掉的字」，
    # 所以它自己抽錯了必須當場叫出來，不能安靜回傳一份少東西的清單。
    # 探針挑開場動畫那串演化字卡 —— 同一個檔案有 6 則連號，record size 只要
    # 算錯一個 byte，第二則之後就會歪掉（第一版寫成 100 bytes 就是這樣）。
    uniq = {r[1] for r in rows}
    probes = ["Modern Day Rex", "Tyrannosaurus Rex", "Slippery Pig calling large obnoxious vessel..."]
    missing = [p for p in probes if not any(p in m for m in uniq)]
    if missing:
        print(f"### 正對照失敗：抽不到已知存在的 {missing} —— 解析有問題 ###")
        return 3
    print(f"  ✓ 正對照：{len(probes)} 個已知字串都抽得到（含同檔連號的第 1 則與第 6 則）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
