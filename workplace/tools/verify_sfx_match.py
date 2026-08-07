#!/usr/bin/env python3
"""正面證據：在遊戲錄音裡找出 REX009.DSR 的音效，證明引擎真的播了它。

為什麼需要這支：
  - 「ini 設了 sfx_volume=255」是輸入，不是證據。
  - 「log 沒有 DSR file not loaded」是否定證據 —— 沒呼叫 playSound 也不會有那行。
  - A/B 對照（sfx 0 vs 255）看得到差異，但分不出「音效的貢獻」與「兩次流程推進
    程度不同」—— 尤其 MADS 的 OPL 音樂走 kPlainSoundType（audio/fmopl.cpp:455），
    根本不受 sfx_volume 影響，音量差不能直接歸因給音效。

這支做的是正規化交叉相關：把每個抽出來的音效當樣板，在錄音裡滑動比對。
遊戲真的播過它，就會在某個時間點出現遠高於背景的相關峰值。
純 Python 實作（容器沒有 numpy），所以先把兩邊都降到 4kHz 單聲道再比，
資料量降到可接受。

用法：
    verify_sfx_match.py <遊戲錄音.wav> <音效目錄> [取樣上限秒]
"""
import array
import math
import os
import struct
import sys
import wave


def read_wav_mono(path, target_rate=4000, max_sec=None):
    """讀 wav → 單聲道、降取樣到 target_rate 的 float list（已去 DC）。"""
    with wave.open(path, "rb") as w:
        ch, width, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        if max_sec:
            n = min(n, int(rate * max_sec))
        raw = w.readframes(n)

    if width == 1:                      # unsigned 8-bit
        samples = array.array("B", raw)
        data = [(s - 128) / 128.0 for s in samples]
    elif width == 2:                    # signed 16-bit
        samples = array.array("h", raw[: (len(raw) // 2) * 2])
        data = [s / 32768.0 for s in samples]
    else:
        sys.exit(f"### 不支援的位元深度：{width * 8} bit ###")

    if ch > 1:                          # 混成單聲道
        data = [sum(data[i:i + ch]) / ch for i in range(0, len(data) - ch + 1, ch)]

    step = rate / target_rate
    if step > 1:
        out = []
        pos = 0.0
        while int(pos) < len(data):
            out.append(data[int(pos)])
            pos += step
        data = out

    if data:                            # 去 DC
        m = sum(data) / len(data)
        data = [x - m for x in data]
    return data


def norm(v):
    return math.sqrt(sum(x * x for x in v)) or 1e-9


def best_match(hay, needle, hop):
    """回傳 (最佳正規化相關值, 對應秒數index)。needle 已正規化。"""
    nlen = len(needle)
    nn = norm(needle)
    best, best_i = 0.0, 0
    i = 0
    while i + nlen <= len(hay):
        seg = hay[i:i + nlen]
        d = norm(seg) * nn
        if d > 1e-9:
            c = abs(sum(a * b for a, b in zip(seg, needle))) / d
            if c > best:
                best, best_i = c, i
        i += hop
    return best, best_i


def main():
    rec_path = sys.argv[1]
    sfx_dir = sys.argv[2]
    max_sec = float(sys.argv[3]) if len(sys.argv) > 3 else 100.0

    RATE = 4000
    print(f"讀錄音：{rec_path}（前 {max_sec:.0f} 秒，降到 {RATE}Hz 單聲道）")
    hay = read_wav_mono(rec_path, RATE, max_sec)
    print(f"  {len(hay)} 取樣點\n")

    # 只用夠長、夠響的音效當樣板；太短的容易假陽性
    cands = []
    for fn in sorted(os.listdir(sfx_dir)):
        if not fn.endswith(".wav"):
            continue
        p = os.path.join(sfx_dir, fn)
        if os.path.getsize(p) < 8000:
            continue
        cands.append((fn, p))

    print(f"{'音效':<14}{'長度':>7}  {'最佳相關':>8}  位置")
    print("-" * 46)
    results = []
    for fn, p in cands:
        needle = read_wav_mono(p, RATE)
        needle = needle[: RATE * 1]          # 取前 1 秒當樣板，夠有辨識度又不會太慢
        if len(needle) < RATE // 2:
            continue
        c, i = best_match(hay, needle, hop=200)   # 每 50ms 滑一次
        results.append((fn, c, i / RATE))
        print(f"  {fn:<12}{len(needle)/RATE:>6.2f}s  {c:>8.3f}  {i/RATE:>6.1f}s")

    if not results:
        sys.exit("### 沒有可用的樣板 ###")

    top = max(results, key=lambda r: r[1])
    print(f"\n最高相關：{top[0]}  {top[1]:.3f} @ {top[2]:.1f}s")
    # 純噪音／不相關訊號的正規化相關通常落在 0.1-0.3；0.5 以上代表確實對到同一段波形
    if top[1] >= 0.5:
        print("✓ 錄音裡找得到 DSR 音效的波形 —— 引擎確實播了數位音效")
        return 0
    print("### 相關性不足 —— 沒有證據顯示錄音裡有 DSR 音效 ###")
    return 1


if __name__ == "__main__":
    sys.exit(main())
