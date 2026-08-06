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
| `HOGANUS.DAT` | 459 段 | — | 防拷題庫，**內容是二進位不是明文**，非翻譯範圍（ScummVM 預設關閉防拷） |
| **合計可譯** | **4,360 則** | **≈ 44,000 字** | 批次切分後 30 批 |

> README 的「N 則對白」用 **4,360 則**（quotes 804 + vocab 1,197 + messages 1,556 組 + txr 807 行）。

## 與 CLAUDE.md 原本假設的差異（實測修正）

| CLAUDE.md §4.1 原本寫 | 實測 |
|---|---|
| ④ `CONV%03d.CNV` 對話樹 | **本作沒有任何 `.CNV` 檔**。對話樹是 Dragonsphere／Phantom 用的；Rex Nebular 的對話走 MESSAGES + QUOTES |
| 物品名要另外處理 | `OBJECTS.DAT` 存的是 **vocab 索引**（`_descId` / `_vocabList[].vocabId`），不含字串 → 物品名全在 `VOCAB.DAT`，不必另抽 |
| 沒提到 | `*.TXR` 是獨立的文字來源（片尾／製作名單），含腳本指令 `[background=962]` `[pan=1,1,6]`，翻譯時要跳過指令行 |
| 沒提到 | `HOGANUS.DAT` 是二進位編碼，不是明文題庫 |

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
