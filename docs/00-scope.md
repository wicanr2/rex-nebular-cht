# 工作量與範圍（實測數據，2026-08-06）

工具：`workplace/tools/mads_res.py`（HAG／MadsPack／FAB）＋ `extract_text.py`。
資料來源：`workplace/game/`（floppy DOS 版，`global.hag` + `section1–9.hag` + `SECTION0.HAG`）。

## HAG 封裝

| 項目 | 數字 |
|---|---|
| HAG 檔 | 11 個（GLOBAL + SECTION0–9） |
| 資源總數 | **1493** |
| 副檔名分佈 | `.SS` 851（sprite）、`.AA` 203（動畫）、`.DAT` 162、`.ART` 136、`.HH` 116、`.INT` 11、`.FF` 5（字型）、`.TXR` 5（文字視圖）、`.DB` 2、`.DSR` 2 |

## 文字資源（全部已抽出，round-trip 可逆性 **PASS**）

| 來源 | 則數 | 英文字數 | 說明 |
|---|---|---|---|
| `QUOTES.DAT` | **804** | 4,090 | 前 48 則是選單／存讀檔 UI，其餘是台詞與旁白。118 行帶 `~` 續行標記 |
| `VOCAB.DAT` | **1,197** | 2,140 | 0–12 是指令動詞，其餘是場景物件與道具名（字母排序），夾雜少量動詞 |
| `MESSAGES.DAT` | **1,556 組 / 6,558 行** | 34,362 | 主體。FAB 壓縮 + 索引表。玩家操作的回應、吐槽、旁白 |
| `*.TXR` | 1,340 行（807 行含英文） | 3,390 | `CREDITS` / `ENDING1` / `ENDING2` / `ENDING4` / `QUOTES`，片尾與製作名單 |
| `*.AA` 內嵌訊息 | **199 則**（50 檔） | 1,900 | **第六個來源**，2026-08-07 才補上。過場動畫的對白與開場字卡，詳見下節 |
| `HOGANUS.DAT` | 459 段 | — | 防拷題庫，**內容是二進位不是明文**，非翻譯範圍（ScummVM 預設關閉防拷） |
| 主選單標籤（`menu:`） | **6 則** | — | 主選單是 bitmap 美術不是文字（見 `docs/30-engine-design.md` §8），走疊繪 |
| **合計可譯** | **4,562 則** | **≈ 46,000 字** | 前五個來源切成 30 批，`.AA` 那 199 則單獨一批，主選單 6 則另計 |

> README 的「N 則對白」用 **4,562 則** —— 這是 `cht-data/rex_cht.tsv` 的**實際筆數**，
> 組成為 quote 801 + vocab 1,193 + msg 1,556 + txr 807 + anim 199 + menu 6。
> 跟上表「可譯」的數字略有出入（quotes 少 3、vocab 少 4）：那幾則是純符號或與別筆重複，
> 沒有對應譯文。**引用數字時以 tsv 的實際筆數為準**，不要拿可譯數當已翻數。

## 第六個文字來源：`*.AA` 動畫內嵌訊息

MADS 的動畫檔（MadsPack 容器）chunk 1 是一個 message 陣列，每筆 **96 bytes**：
`int16 soundId` + `char msg[64]` + 位置 + 兩組 RGB + 起訖幀
（`engines/mads/animation.cpp:74` `AnimMessage::load()`）。
載入在 `Animation::load()` L234，繪製在 L569 `scene._kernelMessages.add(..., me._msg)`。

203 個 `.AA` 檔裡有 50 個帶訊息，共 199 則。

**這些動畫在哪播**：遊戲目錄下的 `*.RES` 是動畫播放清單（純文字，一行一段，
前面帶 `-x -r:b -o:1` 這類播放參數）。把它們展開就知道每組訊息玩家何時看得到：

| `.RES` | 段數 | 內容 | 玩家什麼時候看到 |
|---|---|---|---|
| `rexopen.res` | 31 | 含 `RM951A`／`RM952A`／`RM951B`／`RM952B`（史東辦公室要錢）＋ `RM96*`／`RM97*`（片頭太空戰） | 主選單「Watch introduction」 |
| `rexend1–3.res` | 3／3／8 | 含 `RM938A`（「這七萬五千銀河幣是我賺來的！」） | 三種結局 |
| `DEATH.RES` | 10 | `RM001A1–A10`，死法集錦（「嗨！我是雷克斯！」／「嗨。你死了。」） | 死掉的時候 |
| `EVOLVE.RES` | 1 | `RM001B0`，雷克斯演化字卡 | 彩蛋（不被開場或結局引用） |
| `SETS.RES` | 10 | `RM001C0–C9`，片場導覽＋角色一覽 | 同上 |

沒被任何 `.RES` 引用的（`RM216A`、`RM301A`、`RM302A/B`、`RM307*`、`RM318*`、
`RM319B*`、`RM320A`、`RM321G*`）是**場景腳本直接播的過場**：逮捕、搜身、關牢房、
手術檯、電鋸威脅 —— 全是主線必經。

> 這張表是實測 `*.RES` 得到的，不是推測。原本我以為「片場導覽在開場動畫裡」，
> 但 `rexopen.res` 展開後根本沒有 `RM001C*` —— 那組要另外觸發。
> 猜錯的代價是驗收會找錯地方：截了 130 秒開場動畫，一則動畫訊息都沒照到。

**為什麼會漏**：`extract_text.py` 只認 QUOTES / VOCAB / MESSAGES / TXR / HOGANUS
五個副檔名，`.AA` 在資源清單裡被歸類成「動畫」，沒人想過裡面有字。
實際發現的過程是**看截圖**：太空船場景中央浮著一個看不懂的白色英文字，
一路追下去才發現有第六個來源。

**代價**：Rox、Karg、Xina、Gyrain、Twinkles、Rhotunda、Olga、Boog、Og
這九個角色的名字**只出現在這裡**，其他五個來源逐一 grep 全部零命中 ——
補抽之前，這批名字從未進過翻譯流程。詳見 `docs/20-glossary.md` §4d。

## 與 CLAUDE.md 原本假設的差異（實測修正）

| CLAUDE.md §4.1 原本寫 | 實測 |
|---|---|
| ④ `CONV%03d.CNV` 對話樹 | **本作沒有任何 `.CNV` 檔**。對話樹是 Dragonsphere／Phantom 用的；Rex Nebular 的對話走 MESSAGES + QUOTES |
| 物品名要另外處理 | `OBJECTS.DAT` 存的是 **vocab 索引**（`_descId` / `_vocabList[].vocabId`），不含字串 → 物品名全在 `VOCAB.DAT`，不必另抽 |
| 沒提到 | `*.TXR` 是獨立的文字來源（片尾／製作名單），含腳本指令 `[background=962]` `[pan=1,1,6]`，翻譯時要跳過指令行 |
| 沒提到 | `HOGANUS.DAT` 是二進位編碼，不是明文題庫 |
| **「文字有五個來源」** | **是六個** —— `*.AA` 動畫內嵌訊息（見上節）。§4.1 那句話本身就是錯的 |

## MESSAGES 控制碼分佈（翻譯時必須原樣保留）

| 控制碼 | 出現次數 | 意義 |
|---|---|---|
| `[titleN]` | 1,555 | 對話框標題樣式 |
| `[sentence]` | 1,461 | 句子模式 |
| `[nounN]` | 61 | 執行期填入的名詞 |
| `[nounN:it:them]` 等 | 22 | **英文單複數變化**，中文用不到但不可刪 |
| `[center]` | 10 | 置中 |
| `[numberN]` / `[indexN]` | 17 | 數字／索引代換 |
| `[verb]` | 1 | 動詞代換 |

## 翻譯批次

`workplace/out/batches/`，共 **30 批**：vocab 4 批（300/批）、quotes 7 批、messages 12 批、txr 7 批（各 130/批）。
格式：`key <TAB> 英文原文 <TAB> 譯文`。key 用資源內的 index／id，**不用英文原文當 key**——
原文有大量重複（`ON`/`OFF`/`STILL` 各出現兩次），用內容當 key 會撞。
