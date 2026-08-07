#!/usr/bin/env bash
# 截開場動畫（Watch Introduction）的圖 —— 專門驗證第六個文字來源
# （*.AA 動畫內嵌訊息）有沒有中文化。
#
# 為什麼要單獨一支：record_gameplay_sync.sh 走的是「開始新遊戲」，整段跳過 intro，
# 所以動畫內嵌訊息一張都不會出現在遊玩錄影裡 —— 那 199 則全露英文也照樣「驗收通過」。
#
# 用法：shot_intro.sh <輸出目錄> [起截秒數...]
set -euo pipefail

OUT="${1:?用法: shot_intro.sh <輸出目錄> [秒數...]}"
shift
TIMES=("$@")
[ ${#TIMES[@]} -eq 0 ] && TIMES=(6 12 18 24 30 36 42 48 54 60 66 72)

mkdir -p "$OUT"
export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x24 >/dev/null 2>&1 &
XVFB_PID=$!
cleanup() { pkill -x scummvm 2>/dev/null || true; kill $XVFB_PID 2>/dev/null || true; }
trap cleanup EXIT
sleep 2

/w/scummvm-src/scummvm --path=/w/game --auto-detect >"$OUT/scummvm.log" 2>&1 &
sleep 6

# [雷] 視窗標題不是 "ScummVM" —— 遊戲跑起來之後 ScummVM 會把標題換成
# 「Rex Nebular and the Cosmic Gender Bender」。原本寫死搜 "ScummVM" 一直回空，
# 於是 windowactivate 從來沒執行過，點擊全部落空（畫面完全正常，只是選項按不動）。
find_wid() {
    local w
    for pat in "Rex Nebular" "ScummVM"; do
        w=$(xdotool search --name "$pat" 2>/dev/null | tail -1 || true)
        if [ -n "$w" ]; then echo "$w"; return 0; fi
    done
    xdotool search --name "." 2>/dev/null | tail -1 || true
}

# [雷] set -e 底下不能寫 `[ -n "$wid" ] && { ... }` —— wid 為空時整個 && 回 1，
# 腳本當場退出而且什麼都不印（看起來像 docker 壞掉）。用 if 並明確 return 0。
activate() {
    local wid
    wid=$(find_wid)
    if [ -n "$wid" ]; then
        xdotool windowactivate --sync "$wid" 2>/dev/null || true
        xdotool windowfocus "$wid" 2>/dev/null || true
    else
        echo "  ! 找不到任何視窗"
    fi
    return 0
}
click_at() { activate; xdotool mousemove "$1" "$2"; sleep 1; xdotool click --clearmodifiers 1; }

# 等畫面靜止：連續兩張間隔 2 秒的截圖雜湊相同才算穩定。
# 主選單的選項是**逐項淡入的**，開場那幾秒每一張都不一樣 ——
# 不等它穩定就拿雜湊當判準，等於沒有判準（見下方 [HARD]）。
settle() {
    local a b i
    for i in 1 2 3 4 5 6; do
        import -window root "$OUT/.s1.png"; sleep 2
        import -window root "$OUT/.s2.png"
        a=$(md5sum "$OUT/.s1.png" | cut -c1-8)
        b=$(md5sum "$OUT/.s2.png" | cut -c1-8)
        if [ "$a" = "$b" ]; then echo "$a"; return 0; fi
    done
    echo "$b"
}

MENU_HASH=$(settle)
cp "$OUT/.s2.png" "$OUT/00-menu.png"
echo "=== 主選單穩定於 $MENU_HASH ==="

if [ "${NO_CLICK:-0}" = "1" ]; then
    # attract 模式：什麼都不點，等遊戲自己播 demo。
    # `RM001A*`／`RM001B0`／`RM001C*` 那組動畫訊息（死法集錦、Rex 演化字卡、
    # 片場導覽、角色一覽）不在「Watch introduction」裡 —— intro 是純視覺的
    # 太空旅程動畫，130 秒內一個字都沒有。這批要靠主選單放著不動才會出現。
    echo "=== attract 模式：不點任何東西，等 demo 自動播 ==="
else
    # 主選單第三項「Watch introduction」。選項是美術圖不是文字（font.h:36），位置固定。
    # 三個選項 y = 375 / 415 / 455（實測 00-menu.png 量出來的，不要用間距推算 ——
    # 第一版推成 427，剛好落在「Resume last game」上，沒存檔所以完全沒反應）。
    click_at 350 455
    sleep 3
    import -window root "$OUT/01-after-click.png"
    AFTER=$(md5sum "$OUT/01-after-click.png" | cut -c1-8)

    # [HARD] 判準本身要做正對照。
    # 第一版寫的是「點擊前後雜湊不同 → intro 已開始」，跑起來確實「通過」了 ——
    # 但截出來的八張全是主選單。原因：主選單的選項在淡入，畫面本來就一直在變，
    # 這個判準對「什麼都沒發生」也會回報成功。
    # 改成先等畫面靜止拿到 MENU_HASH，點擊後再比 —— 這樣「沒反應」就真的會被抓到。
    if [ "$AFTER" = "$MENU_HASH" ]; then
        echo "### 點了「Watch introduction」畫面還停在主選單（$AFTER）—— 點擊沒生效 ###"
        exit 3
    fi
    echo "=== 畫面 $MENU_HASH → $AFTER，已離開主選單 ==="
fi

PREV=0
for t in "${TIMES[@]}"; do
    sleep "$((t - PREV))"
    import -window root "$OUT/f${t}.png"
    echo "  截 ${t}s"
    PREV=$t
done

rm -f "$OUT/.s1.png" "$OUT/.s2.png"
echo "=== 完成，共 ${#TIMES[@]} 張 ==="
