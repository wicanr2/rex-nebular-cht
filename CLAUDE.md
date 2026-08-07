# CLAUDE — 錯體奇航（Rex Nebular and the Cosmic Gender Bender）繁體中文化

> 專案根目錄 `/home/anr2/scummvm/rexnebular/`。引擎是 **MADS**（ScummVM `mads` engine，gameid **`nebular`**），**不是 SCUMM**。
> 蒸餾自 `../CLAUDE-SCUMMVM-SCUMM-ENGINE.md`（SCUMM 模板）與 `../CLAUDE-SCUMMVM-AGI-SCI-Template.md`，但**核心工法不同**：SCUMM 的「零 patch」在 MADS 不成立，理由見 §3。
> 命中即載：skill `re-retro-cht-rulebook`（動手前先查路由表）、`eten-bitmap-font`、`retro-avg-taiwanese-localization`（成人喜劇在地化 + 批次翻譯 fan-out）、`dev-setup-bundle`、`game-promo-video-ffmpeg`、`cjk-package-encoding`；rulebook `81`（拉畫布非縮字）、`83`（完整性優先）、`35`（背景 build liveness）、`45`（成本分工）、`93`（配樂原版素材）。

---

## 1. 身分與 interaction

- 這款遊戲的繁中化工作分身：**抽字 → 上網補中文資料 → 翻譯／在地化 → 烘字型 → 引擎中文路徑 → 實機驗證 → 打包**。
- **動手前先問清楚**：需求不完整時先問「要做這件事必須釐清的問題」再開工。
- **啟動檢查點**：接到分析原始碼／除錯／規劃／打包任務，動手前先查 `re-retro-cht-rulebook` 路由表逐列比對，命中就先 Read 對應 kb／rulebook 再做——別憑記憶跳過。**「任務開始」不只是使用者剛開口那一刻**，長跑實驗每一輪、連兩輪同類失敗、要下「有效／無效」結論前，都要回來查表。
- 語言與文風：助理輸出、文件、commit、註解一律繁體中文；程式碼保留原語言。中性客觀，避免浮誇／絕對化用詞；不貼導引式 meta 標籤（「白話：」「用途：」）。
- 產出物位置：規劃／設計／譯名表／roadmap 一律 markdown 放進專案 repo 的 `docs/`，隨 commit 進版控。**不放 Claude Artifact**。

---

## 2. 素材清單（都在本目錄底下，不必另尋）

| 檔案 | 內容 | 用途與注意 |
|---|---|---|
| `Rex Nebular And The Cosmic Gender Bender (Floppy DOS).zip` | 遊戲本體（floppy DOS，1996 檔期戳）。`global.hag`＋`section1–9.hag`＋`SECTION0.HAG`＋`*.RES`＋`asound/isound/psound/rsound.*` | 解到 `game/`（gitignore）。**絕不入公開 repo** |
| `DDSC-J-00084-遊戲手冊：錯體奇航.pdf` | **當年中文遊戲手冊，10 頁**（實際約 20 個版面） | **官方在地譯名唯一一手來源**。[HARD] **純掃描圖、無文字層**，`pdftotext` 抓不到任何字 → 必須 `pdftoppm -r 110 -png` 轉圖後用 Read 判讀（或 OCR），判讀結果要標信心等級 |
| `rexnebular-manual.pdf` | 英文原版手冊（Acrobat Paper Capture OCR） | 有文字層但 OCR 品質普通（`In5"tallation`、`MicroPros€` 這類殘字）。**用途：防拷題庫、術語原文、引言素材**；引用前先跟掃描圖對照 |

- 遊戲原始 zip 內沒有安裝程式版的 `mpslabs.001/.idx`，是**已解壓的資料檔**（`global.hag` 那組）；ScummVM 的 detection table 兩種都收，實際落哪一筆等 `--list-games` 實測確認，別先假設。

---

## 3. [HARD] 最重要的一條：這款**必須改 ScummVM 引擎**，零 patch 不成立

SCUMM 模板的最高原則是「零 source patch」，那是因為 SCUMM 引擎本來就有 CJK 路徑與 ZH_CHN 白名單。**MADS 沒有**。一手證據（ScummVM 2.8.0，`engines/mads/`）：

```cpp
// engines/mads/font.cpp:180  Font::writeString()
char theChar = (*text++) & 0x7F;          // ← 每個位元組被強制遮成 7-bit
int charWidth = _charWidths[(byte)theChar];
```

`_charWidths` / `_charOffs` 只開 **128 格**，繪字迴圈按 2bpp 比例字展開。任何 ≥ 0x80 的位元組（Big5 lead byte 必然 ≥ 0xA1）會被 `& 0x7F` 折成一個 ASCII 字元 → **中文在 MADS 沒有任何「挑碼空間就能繞過」的空間**。

同時 `detection_tables.h` 的 11 筆 `nebular` entry **全部 `Common::EN_ANY`**，引擎沒有任何非英文語言分支。

**所以本專案的最高優先原則改寫為：**

> 正確性 / 引擎對齊 ＞ **最小且集中的 patch** ＞ 可玩交付 ＞ 可維護 / 文件 ＞ 效能 / 美觀。

「最小且集中」的操作定義（違反就是走偏了）：
- 中文邏輯集中在**新增檔案**（`mads/cht_font.cpp/h`、`mads/cht_text.cpp/h`）＋**既有檔的少數 hook 點**；不散落到 scene / player / sequence。
- 每個 hook 點都要能一句話說出「它為什麼非改不可」。說不出來 → 回去想架構，不要見坑填坑（`rulebook/41`）。
- **不改遊戲資料檔**（HAG 內的 `.DAT`／`.CNV` 一個 byte 都不動）→ 見 §5 的替換表路線。公開 repo 天然 patch-only。

---

## 4. MADS 引擎領域事實（動手前的地基，全部有一手出處）

### 4.1 文字有**六**個來源，少抽一個就露英文

| # | 來源 | 格式 | 出處 | 難度 |
|---|---|---|---|---|
| ① | `*QUOTES.DAT` | **null-terminated 明文字串陣列**，全載進 `_quotes`，`getQuote(index)` 取用（index 從 1 起） | `game.cpp:346 loadQuotes()`、`game.h:169` | 低 |
| ② | `*VOCAB.DAT` | null-terminated 明文，`Scene::getVocab(id)` → 指令表／名詞（畫面左下 verb 列與物品名） | `scene.cpp:257` | 低 |
| ③ | `*MESSAGES.DAT` | **FAB 壓縮 ＋ 索引表**（id/offset/size），`Game::getMessage(id)` 解壓後切成字串陣列 | `game.cpp:368` | **回填難**（要重壓或改讀未壓縮） |
| ④ | `*.TXR` | TextView 文字（片尾／製作名單），含腳本指令行 `[background=962]` `[pan=1,1,6]` | `menu_views.cpp` TextView | 低 |
| ⑤ | 引擎硬寫字串 | `staticres.cpp`（`"Walk to "`、`"Look around"`、介係詞 `with`/`to`/`at`/`from`/`on`/`in`/`under`/`behind`）、`nebular/dialogs_nebular.cpp`（防拷提示等） | 原始碼 | 低但**最容易漏** |
| ⑥ | `*.AA` **動畫內嵌訊息** | MadsPack chunk 1，每筆固定 **96 bytes**（`int16 soundId` + `char msg[64]` + 位置 + 兩組 RGB + 起訖幀）。203 檔中 50 檔有訊息，共 **199 則** | `animation.cpp:74 AnimMessage::load()`、載入 L234、繪製 L569 | 低但**最容易漏掉整包** |

- ①②③④⑥ 都封在 `GLOBAL.HAG` / `SECTION%d.HAG`（`resources.cpp:183`），`*` 前綴代表走 HAG 查找。
- **[實測修正 2026-08-07] ⑥ 是後來才發現的，本檔原本寫「五個來源」。**
  漏掉的代價：過場對白（逮捕／搜身／手術檯／片頭太空戰）全露英文，而且 **Rox、Karg、
  Xina、Gyrain、Twinkles、Rhotunda、Olga、Boog、Og 九個角色的名字只存在於這裡** ——
  其他五個來源逐一 grep 全部零命中。
  **發現方式是看截圖，不是任何自動檢查**：太空船場景中央浮著一個看不懂的白色英文字，
  追下去才挖出整個來源（那個字最後查明是原作 sprite 美術，跟它無關 —— 但沒去追就不會發現）。
  **教訓**：「抽字工具跑完沒報錯」證明不了完整性。要證明完整，得反過來問
  「畫面上每一個看得到的字，我能不能說出它從哪個來源來」。
- **[實測修正 2026-08-06]** 本作**沒有任何 `CONV*.CNV` 對話樹檔**（那是 Dragonsphere／Phantom 用的），
  對話走 MESSAGES + QUOTES；`OBJECTS.DAT` 存的是 **vocab 索引**不是字串，物品名全在 `VOCAB.DAT`，
  不必另抽；`HOGANUS.DAT`（防拷題庫）是二進位不是明文。實測數據見 `docs/00-scope.md`。
- **[HARD] 介係詞是拼句子用的**：`kArticleList` 把 verb + 名詞 + 介係詞組成 `Throw Log at Bulkhead` 這種指令行。中文語序不同（「把船長日誌丟向艙壁」），**不能逐詞替換了事**，要在組句處理一次語序。這是本專案最需要設計、也最容易做爛的一塊，先寫設計文件再動手。

### 4.2 字型：5 個 `.FF`，選單是**美術圖不是文字**

```
FONT_CONVERSATION "*FONTCONV.FF"   FONT_INTERFACE "*FONTINTR.FF"
FONT_MAIN "*FONTMAIN.FF"           FONT_MISC "*FONTMISC.FF"     FONT_TELE "*FONTTELE.FF"
FONT_MENU "*FONTMENU.FF"  // font.h:36 註解：Not in Rex (uses bitmap files for menu strings)
```

- `.FF` 是 MadsPack 壓縮的 **2bpp 抗鋸齒比例字**（`_fontColors[4]`，每 2 bit 一個像素索引），比 SCUMM 的 1bpp 點陣講究。
- **[HARD] 主選單文字是 bitmap 美術**（font.h 一手註解）→ 主選單中文化 = **改圖**，不是換字型。歸類到 baked-art，工作量與對白翻譯無關，排期要分開算。
  - **[已完成 2026-08-07]** 走的是「不動原美術」：7 個 sprite（`RM990A1–A7.SS`，各 14 幀）
    的淡入動畫照跑，跑完在 `MainMenu::doFrame()` 收掉 sprite，改在文字層畫譯名
    （`ChtSupport::drawToLayer`，key `menu:0`–`menu:5`）。點擊範圍是 `display()`
    註冊在 `screenObjects` 的，跟 sprite 在不在無關，收掉照樣點得動。
  - **字色從原圖統計，不要自己挑索引**：主選單會 `resetGamePalette()` 換調色盤，
    挑一個常數等於賭它在那張盤裡剛好是黃的。取原 sprite 用最多的非透明色（實測五項一致 index 236）。
  - **[雷] `SpriteSlots::reset()` 預設是 `reset(true)`**，會連 `_scene._sprites.clear()`
    一起做 —— 那會 `delete` 掉每個 `SpriteAsset`（含 `_menuItems[]`）。收完再 `getFrame()`
    就是 use-after-free：w/h 讀回 `2386x-8892` 然後 segfault。要 `reset(false)`，
    而且**先把座標與字色算完再收**。
- 中文字**不要塞進 `.FF`**：`.FF` 結構被 128 格上限鎖死。正解是另開一份 Big5 點陣字庫（`rex_big5.fnt`），走獨立繪字路徑。

### 4.3 畫布 320×200 → [HARD] 拉畫布，不縮字

`screen.h:32` `MADS_SCREEN_WIDTH 320` / `MADS_SCREEN_HEIGHT 200`，`mads.cpp:169 initGraphics()`。

依 `rulebook/81`：**預設拉高內部畫布到 640×400（原解析整數倍、底圖 nearest 放大保持銳利），中文用 16×16 或 24×24 正常尺寸畫在放大後的畫布**。不要把中文縮到 8px 塞原字位（糊成一團），也不要硬把 24px 畫進 320 寬（UI 全破版）。這條**不用再問使用者**，除非明確另行指定。

- 座標重映射：UI／hotspot／滑鼠命中區都是為 320×200 排的 → 要一起映射，別漏 hit-test。
- MADS 沒有 ScummVM SCI 那種現成 `GFX_SCREEN_UPSCALED_640x400` 咽喉點，**要先確認**是自改畫布常數（recipe 1）還是有可站的 upscale 點（recipe 6）。**先印出目標 buffer 的實際尺寸再寫座標**，別靠假設（LSL1 就是在這裡把 320 當成 640 導致 overlay 整個不畫）。

### 4.4 中文開關：不能用 `--language`

- 11 筆 detection entry 全 `EN_ANY`；照 AGI 的教訓（設非英文語言會讓 detector 行為改變、遊戲進不去），**用「字型檔存在」當開關**：遊戲目錄有 `rex_big5.fnt` ＋ `rex_cht.tsv` 就啟用中文，開檔失敗就 `_chtEnabled = false` 維持英文原樣。
- 引擎裡判 `chtEnabled()`，**不要判 `getLanguage()`**。
- **[HARD] init 順序**：凡「建構子時抓一次狀態」的字串（系統 UI、狀態列），要確認 `loadChtResources()` 在該建構子**之前**執行，否則中文分支不生效（LSL1 的 `SystemUI` 就踩過）。

### 4.5 防拷：ScummVM 預設關閉，免 patch

```cpp
// engines/mads/nebular/game_nebular.cpp:46
ProtectionResult GameNebular::checkCopyProtection() {
    if (!ConfMan.getBool("copy_protection"))   // 預設 false
        return PROTECTION_SUCCEED;
```

題庫在 `HOGANUS` 資源（`dialogs_nebular.h:74`），問手冊裡的字。**別自加跳過 patch**（柵欄原則：upstream 已經處理）。要驗證就 pristine ScummVM headless 實測一次「不答題直接進遊戲」。

---

## 5. 建議工法：引擎端替換表，不改遊戲資料

沿用 SCI／AGI 軌驗證過的路線——**不改遊戲資源，只 patch 引擎 ＋ 執行期查表替換**：

```
英文原文（或 quote index）當 key  →  查 rex_cht.tsv  →  回傳 Big5 譯文  →  中文繪字路徑
```

理由是第一性的，不是偏好：
- ③ `MESSAGES.DAT` 是 **FAB 壓縮 ＋ 偏移索引表**，就地回填要重算全表偏移並重壓；替換表路線完全繞開這件事。
- 遊戲資料一個 byte 不動 → **公開 repo 天然 patch-only**（碼表＋譯文＋字型＋工具＋文件），無版權素材外流風險。
- 換一版遊戲資料（floppy／CD／installer 版）不必重做回填。

代價要認：多一層查表、key 要穩定。取捨紀錄寫進 `docs/`，別讓後人以為只是隨手選的。

**[HARD] 先做可逆性證明再動文字**：抽 ①②③④⑥ → 原封不動寫回／重組 → **diff = 0**。這一步沒過，後面全部是沙上建塔。

---

## 6. [HARD] 上網收集中文資料與攻略（本專案專章，別省）

這款在台灣**沒有公開的中文化前例、也查不到中文攻略**（2026-08-06 查證，見下），所以「網路上找得到什麼」本身就是要主動維護的資產。**每個新階段開工前跑一輪，把結論寫進 `docs/10-references.md`，附查詢日期與查詢字串。**

### 已完成的一輪（2026-08-06）

| 查詢 | 結果 |
|---|---|
| `錯體奇航 Rex Nebular 中文 攻略` | 無中文攻略，只回英文資源 |
| `"錯體奇航" ... MicroProse 手冊` | 無命中 |
| `Rex Nebular 汉化 中文版 ScummVM MADS` | **查不到任何中文化／汉化專案**，只回 ScummVM 官方相容性頁與 bug tracker |
| `"錯體奇航" OR "雷斯" ... 1992 MicroProse` | 無命中 |
| 台灣中文冒險解謎遊戲清單（chiuinan.github.io）逐條比對 | **無此條目** → 當年很可能沒有正式中文版遊戲，只有中文說明書 |

> **[HARD] 「查詢回空」不等於「不存在」**（見 `~/diagnosis-notes/docs/02-query-returned-empty/`）。上面只證明「以這些字串、在這些引擎索引得到的範圍內沒找到」。要下「沒有前人做過」的結論前，至少再做一次**正對照**（用同樣方式搜一款已知有中文化的老遊戲，確認搜法本身有效），並補搜簡中站（如遊民星空、老遊戲吧）、Internet Archive、abandonware 站的中文資源。

### 英文參考資源（已確認可用）

| 用途 | 來源 |
|---|---|
| 完整流程攻略 | GameFAQs（作者 Abadoo）、Adventure Gamers walkthrough 頁 |
| 逐段實機影片（對照畫面與台詞情境） | YouTube 全流程 playthrough playlist |
| 劇情／笑點結構（翻譯前理解「哪裡是梗」） | TV Tropes 條目 |
| 版本／發行事實 | Wikipedia、ScummVM 相容性頁（`mads:nebular`） |

- **[HARD] 素材用自己的話重寫**：攻略、TV Tropes、當年雜誌廣告都可當理解素材，**不逐字翻、不逐字抄**（著作權不屬本專案）。
- 攻略的價值不只是通關：**它是「這句話出現在什麼情境」的 oracle**。翻譯 `QUOTES.DAT` 時大量句子脫離上下文（`_quotes` 是一整包字串），照字面翻必翻錯——查攻略／影片確認情境，比多翻兩百句更值錢。

---

## 7. 譯名：以當年中文手冊為準（已判讀出的種子表）

**[HARD] 譯名沿用當年官方在地版，不憑印象改**。下表由 `DDSC-J-00084` 手冊掃描圖判讀（來源：手冊第 2–13 個版面）。標「★」者字形在掃描件上清楚；未標者建議二次複核。

| 英文 | 中文（手冊） | 備註 |
|---|---|---|
| Rex Nebular and the Cosmic Gender Bender | **錯體奇航** ★ | 遊戲正式中文名 |
| Rex Nebular | **雷克斯‧尼布勒** ★ | 內文多以「雷克斯」簡稱 |
| Rex 的太空船 *Slippery Pig* / the Pig | **油豬號** | 手冊 300dpi 複核 ＋ 遊戲文字 `the "Slippery Pig"` 交叉印證 |
| Log | 船長日誌 ★ | 道具 |
| Rebreather | 水中呼吸器 ★ | 道具 |
| Binoculars | 望遠鏡 ★ | 道具 |
| Escape Hatch | 逃生艙 ★ | 場景物件 |
| Bulkhead | 艙壁 ★ | 場景物件 |
| Refrigerator / Burger | 冰箱 / 漢堡 ★ | 場景物件 |
| View-screen | 螢幕 ★ | 「Look at View-screen」＝看螢幕 |
| Video Game | 電動玩具 ★ | 「Play Video Game」 |
| Main Commands | 指令表 ★ | UI 區塊（畫面左下） |
| Inventory List | 物品欄 ★ | UI 區塊 |
| Special Commands | 此物品的特殊指令 ★ | UI 區塊（畫面右下） |
| 3-D Image of Selected Object | 立體旋轉中的物品 ★ | UI 區塊 |
| Look | 觀看 ★ | verb |
| Story Line: Naughty / Nice / Locked-Nice | **限制級 / 輔導級 / 乖寶寶級** ★ | 見 §8 |
| Start a new game | 開始一個全新的遊戲 ★ | 主選單 |
| Resume last game | 由上次離開之處繼續遊戲 ★ | 主選單 |
| Watch Introduction | 觀賞動畫開幕篇 ★ | 主選單 |
| Credit | 遊戲製作小組一覽 ★ | 主選單 |
| Exit | 離開遊戲回到 DOS 之下 ★ | 主選單（本作改為「離開遊戲」） |
| Standard / Easy（滑鼠） | 標準型 / 簡易型 ★ | 設定 |
| Still / Spinning（物品顯示） | 靜止型 / 旋轉型 ★ | 設定 |
| Animated | 活動型 ★ | 設定 |
| Smooth / Fast / Medium（畫面切換） | 平滑型 / 快速型 / 中等型 ★ | 設定 |
| No Sound | 無聲勝有聲 ★ | 設定（當年譯法，保留） |

- **開工第一件事**：把整本手冊 20 個版面判讀完，補成 `docs/20-glossary.md`（統一譯名表），**批次翻譯的每個 subagent 都先 Read 這一份**，否則譯名必漂移（LSL1 實測：一個姓氏跑出三種寫法）。
- verb 列完整清單（`Walk to` / `Look at` / `Talk to` / `Take` / `Push` / `Pull` / `Open` / `Close` / `Throw` / `Read` / `Swim to` / `Go` / `Disassemble` / `Use`）手冊只中譯了一部分，其餘自訂後入表，**一經定案不得中途改**（verb 會出現在組句裡，改一個要重掃全譯文）。

---

## 8. 在地化尺度（已與使用者定案，2026-08-06）

> **色在雙關、笑在自嘲、賤在旁白——露骨留白，台語提味，年代感點到為止。**

| 維度 | 定案 |
|---|---|
| **色色尺度** | **點到為止靠雙關**：字面乾淨、諧音聯想、露骨留白，對齊原作 double entendre 的手法 |
| **台味濃度** | **中度提味**：口語國語為主，情緒點插少量台語詞（歹勢／衰／凍未條／齁啦語尾），不整句台語 |

- **翻譯 ≠ 在地化**：這款靠的是笑點，直譯會讓笑話涼掉。手法對照（梗庫）見 kb `retro-avg-taiwanese-localization` 增量三：死法旁白用社會版標題腔、主角台詞用自嘲魯蛇、性暗示走諧音雙關。
- **[HARD] 分寸**：涉真人／政治／族群諧音一律避開；原作年代的性別歧視玩笑改成「雷克斯自己很衰很糗」；族裔口音刻板笑話拿掉口音。
- **本作特有：Story Line 三級是遊戲內建機制**（`GAMEOPTION_NAUGHTY_MODE`，`detection.h:51`／`metaengine.cpp:81`）。遊戲原本就依分級走**不同文字**。
  - [HARD] 抽字時**必須確認「限制級／輔導級」兩套文字是不是都在資源裡**，別只翻到其中一套就宣稱完成（`rulebook/83` 完整性優先）。
  - 譯文的尺度校準要**分級套用**：限制級走上面定案的「點到為止雙關」，輔導級照原作口徑收斂，不要兩級翻成同一個味道。
- 規模化流程（照 LSL1 驗證過的管線）：抽可在地化句 → 切批（~130 則/批）→ **先試作一批給使用者看品質**再 fan-out → 共用 `LOCALIZE_INSTRUCTIONS.md`（風格尺度＋硬規則＋統一譯名表）→ 合併驗證（逐行核對 key 與控制碼數量）→ 譯名一致性掃描 → 非 Big5 字 `corrections.tsv`。用 sonnet 不用 haiku。

---

## 9. 字型：預設倚天點陣字

- **[HARD] 16×16 / 24×24 一律優先用倚天中文系統（ETEN）原生點陣字**，那是 1990s DOS 中文的原貌；WQY/TTF 縮到這個尺寸會糊、比例不對。TTF 只當 Big5 缺字的 fallback。
- 一定要一起帶 `SPCFONT.15`（全形標點 408 字）：`STDFONT` 從「一」(A440) 起、**不含全形標點**，只帶它會讓 `，。！？「」（）` 全掉 fallback，畫面變成「字是倚天、標點是別的字型」。
- 索引是 **Big5 分區**（符號區／常用區／次常用區三段），不是線性。驗收 oracle：`STDFONT.15` 的 `idx=0` 必須是「一」，「中」(A4A4)／「猴」(B555) dump 成 ASCII art 要可辨識。過不了就是索引錯，先別往下做。
- 完整格式與公式見 kb `eten-bitmap-font`。
- **本專案的字型選擇（開工時填這張表）**：

| 設定 | 採用 | 備選 |
|---|---|---|
| 字型 | 待定（建議倚天 24×24 明體 `STD.24M`） | 倚天 24 點五種（明／楷／黑／圓／宋）｜倚天 16×15（只有明體）｜任意 TTF |
| 字模尺寸 | 待定（640×400 畫布下建議 16×16 或 24×24） | — |
| 排版格 | **與字模尺寸解耦**：格寬固定、字模格內置中 `ox=(cellW-glyphW)/2` | 做到這點才能換字體不破版、不疊字 |

- MADS 的 `.FF` 是 2bpp 抗鋸齒，中文若用 1bpp 會在同一畫面看得出「英文有邊緣柔化、中文是硬邊」。**先做一張對照截圖再決定**要不要為中文做 2bpp（成本：字庫大一倍、烘字要做抗鋸齒判斷）。這是可延後的優化，不是開工必須。

---

## 10. 環境（docker-first）

- [HARD] 編譯一律走 docker；Python 一律 docker uv.venv，不污染系統環境。
- 一個 image 打通開發／擷取／影片／打包：

```dockerfile
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git pkg-config libsdl2-dev libfreetype6-dev \
    xvfb x11-utils xdotool imagemagick ffmpeg poppler-utils \
    python3 python3-pil fonts-wqy-microhei fonts-noto-cjk \
    zstd zip unzip curl file && rm -rf /var/lib/apt/lists/*
```

- 本專案**要自編 ScummVM**（因為要 patch），官方預編 binary 只能拿來當「原版對照組」。
- 長指令用 `timeout` 包；headless 用 `Xvfb :99` + `import -window root` 截圖（用 Read 看，**不開 GUI viewer**）；**禁 sentinel 輪詢**（`rulebook/35`）。
- **[HARD] 不碰共用 docker 資源**：只清理自己這次建立的容器（`--rm` 或用完 `docker stop/rm` 自己那幾個）。**一律禁止** `docker image/system/volume/builder/container prune`、`docker rmi`——這台機器同時放著多個客戶專案的 image。要空間就列候選清單請使用者決定。
- 派 subagent 時，上面這條**要明文寫進 prompt**，並列出「不准改哪些目錄」與「不准做的收尾動作」。沒寫的就等於允許。

---

## 11. 實機驗證（headless，`rulebook/65`）

- `Xvfb :99` + 自編 `scummvm --path=/game --auto-detect` + `import -window root` 截圖。
- **驗收＝對 reference 實測，不是內部訊號**：測試綠、log 沒紅字都不算數，要看畫面。
- 檢查清單：verb 指令表全中文、對白逐字正確、**無字元級亂碼**、標點不掉 fallback、換行不切半個字、物品欄與特殊指令欄不破版。
- 場景覆蓋：Rex 的太空船（開場）→ 星球地表 → 水下 → 城市，各取一張。**跑了 N 個場景就要看完 N 張**，只看幾張不准下「都對了」的結論。
- 防拷：確認 ScummVM 預設 `copy_protection=false` 下直接進遊戲（§4.5）。
- ScummVM `debugger` 的場景跳轉在 intro／過場期間可能無效（SCI 實證過），**畫面沒反應先確認遊戲有沒有真的跑起來**，別急著怪 xdotool 或容器。

---

## 12. 打包（`dist-all/` 慣例）

產物一律進單一 `dist-all/`（gitignore、每平台留最新一份）。因為要自編，三平台都走自編路線：Linux **AppImage**、Windows **mingw 交叉編**、macOS 走 `mac-app-cross-pack` skill。以下每一條都是別的專案**實際踩過**的：

- **[HARD] configure 偵測不到函式庫不會報錯，只會安靜把選項關掉** → 建置腳本收尾必須反查：`grep -q "^USE_FLAC = 1" config.mk || exit 3`，同理 vorbis/mad/png/freetype/**mt32emu**。「編得過」不等於「有編進去」。
- **[HARD] `make install` 的資料檔要挑著帶**：全套 `engine-data` 約 59MB，只編 MADS 時絕大多數用不到（`fonts-cjk.dat` 37MB、`Roland_SC-55.sf2` 3.2MB…）。保留清單：`scummremastered.zip`（**預設主題，漏帶會 fallback to builtin**）＋`scummmodern.zip`＋`scummclassic.zip`＋`fonts.dat`＋`encoding.dat`，約 6.5MB。驗證要**另跑一次 launcher GUI** 看主題有沒有破。
- **[HARD] 包驗收要同時比中文資料 md5 **與**引擎指紋**：把引擎目錄所有 `*.cpp`/`*.h` 排序後雜湊成 12 碼寫進 `cht-data/ENGINE.txt`。只比資料的驗收，對「只改引擎」是完全的盲區（Gobliiins 踩過：六個包全 ✓，其中兩個裝的是修正前的引擎）。macOS 的指紋要由 CI 從 runner 上實際編出那顆 binary 的樹算，且 macOS **沒有 `sha256sum`**（用 `shasum -a 256`）。
- **Windows zip 六條**（每條在 Linux 上都測不出來）：`zip -UN=UTF8` ＋ 包內檔名純 ASCII｜`.bat` 換行 CRLF｜`.bat` 內容純 ASCII（中文放 README）｜`.bat` 要 `if errorlevel 1` ＋ `pause`｜README 補 UTF-8 BOM｜附 `scummvm.ini` 鎖 `gui_language=en`。細節見 kb `cjk-package-encoding`。
- **啟動器跨平台通則**：啟動器是「程式旁邊的一支腳本」，**不要動平台自己的啟動機制**（不改 `Info.plist`、不把 script 塞進 `Contents/MacOS/`）；失敗必須讓玩家看得到訊息；設定檔用預先寫好的 UTF-8 靜態 ini ＋ 啟動器只負責複製（不要在 `.bat` 裡 `echo` 中文）；ini 走相對路徑；設定檔寫在包內、不要污染玩家全域 ScummVM 設定。
- **[HARD] MT-32 在這款做不到，`--enable-mt32emu` 一律關掉**（2026-08-07 實測定案，別再試）。三條路全堵：
  - ScummVM 的 **MADS 引擎沒有 MIDI 路徑**。`SoundManager` 建構子直接 `_opl = OPL::Config::create()`（`engines/mads/sound.cpp:45`），那是唯一的音樂裝置；全引擎 grep `MidiDriver` / `MidiParser` / `detectDevice` / `MT_MT32` **零命中**。`_preferRoland` 在 `sound.cpp:43` 寫死 `false`，且只有 `phantom/` 讀它（選音效編號用），nebular 完全不碰。**`-e mt32` 對這款是靜默無效的**——不報錯、不退化提示，就是照放 AdLib。
  - 遊戲 zip 裡 **56 個檔全是資料，沒有 `.EXE`** → DOSBox + Munt 跑原版這條也不通。
  - `rsound.001–009`（Roland 驅動）**不是音樂資料，是 16-bit DOS 執行檔**：檔頭 `4d 5a`（MZ），內含 `RLND AGAdemo 9-13-92`；`asound.*` 同型（`AGAAdlibOvl1`）。ScummVM 是把 asound 的行為**重新實作**成 C++，沒人做 rsound。要 MT-32 等於逆向那九支驅動重寫 MIDI 輸出，是獨立專案的規模。
  - **驗證方法（下次遇到類似狀況照做）**：不要信「我設了參數」，錄一份 AdLib、錄一份宣稱 MT-32 的，`showspectrumpic` 產兩張頻譜圖比對。諧波結構與脈衝間隔同型 = 根本沒切換。本次就是這樣抓到的。
  - Munt 對這款完全無用，編進去只是把 binary 撐肥 → 三平台一律 `--disable-mt32emu`，並反向反查 `config.mk` 沒有 `USE_MT32EMU = 1`。`*.ROM` 仍一律 gitignore。
- **[HARD] 防呆腳本寫完做正對照**：造一個「六條全違反」的 zip 餵進檢查腳本，確認每條都叫得出來。「沒有紅字」有兩種可能——包是好的，或**檢查自己壞了**。
- [雷] `pkill -f <pattern>` 會命中 bash 自己的命令列、把執行中的那行 shell 殺掉（無聲中止、exit 144，看起來像 docker 壞掉）。收尾清理用 `pkill -x <程序名>` 或先取 PID。
- 打包／等 CI 這類機械活**派 sonnet/haiku subagent 前景阻塞、有界執行**（`rulebook/45`）；旗艦只看「進遊戲」截圖 ＋ leak-scan。

---

## 13. README 開頭引言 — [HARD] 交付必備，不要等使用者提醒

**引言 = README 第一個 `##` 之前的區塊**，任務是「讓沒玩過這款的人三十秒內想玩」。它是**故事**，不是規格。

結構（六段，順序固定）：
1. **H1**：`錯體奇航 — 中文副標　繁體中文化`
2. （選）英文原名，斜體一行。
3. **敘事 1–2 段，每段 2–4 句，合計 100–200 字**：第 1 段寫主角處境（只用**開場十分鐘內**就成立的事實，不劇透）；第 2 段寫轉折。第二人稱「你」或貼著主角的第三人稱。這款是喜劇，語氣就寫得衰一點。
4. **轉場段，必須帶具體數字**——「把這條路上的每一句話——N 則對白、M 個指令、存讀檔介面——翻成繁體中文」。
5. **patch-only 免責 ＋ 指路**：一句話說明只有碼表／譯文／字型、不含遊戲，接「想直接玩，跳到〈怎麼玩〉」。
6. **中文標題截圖**（有宣傳片就放連結／靜音 GIF）。

紅線：
- **[HARD] 不要維基句／型錄句開頭**——「《X》是 Y 公司於 19NN 年推出的 Z 類型遊戲」是最常見的失敗樣態。**年份、引擎、開發商不准出現在引言裡**，全部往下挪到版本對照表。
- 不貼 meta 標籤（「引言：」「劇情簡介」）；不劇透；不翻譯腔；不吹（時代註腳如當年售價、磁片數比形容詞有力）。
- 長度：H1 到第一個 `##` 之間 ≤ 300 字。

收工檢查：□ 第一個 `##` 前是敘事不是定義句 □ 敘事段沒有年份／引擎／公司名 □ 有具體數字 □ 有 patch-only 免責與指路。

README 本體：在地代理史（**這款當年只有中文手冊、沒有中文版遊戲，本身就是好故事**）＋譯名對照＋技術深潛（`& 0x7F` 那段值得寫）＋怎麼玩。寫法見 `rulebook/80`，寫完過一遍 `90`（白話）＋ `91`（去 AI 味）。

---

## 14. 推廣（選用但加分）

- 宣傳片：x11grab 錄**真實遊玩片段** → ffmpeg 合成標題卡＋片段＋中文字幕（靜態 + fade，**不用 zoompan**）。
- **[雷] x11grab 跑起來之後，`xdotool click` 會送不進 ScummVM 視窗**（2026-08-07 實證）。
  症狀極具欺騙性：`mousemove` 照常生效、游標停在正確的選項上、畫面完全正常，
  **但流程整段停在主選單**——第一次錄了 115 秒全是主選單才發現。
  單錄音訊（沒有 x11grab）時同樣的座標是好的，所以這是 x11grab 引入的。
  修法：每次點擊前 `xdotool search --name ScummVM | tail -1` 取 wid，
  `windowactivate --sync` + `windowfocus` 再點。
- **[HARD] 錄完要驗「有沒有真的進遊戲」**，而且驗的方式要先做過正對照。
  - **不能用 ScummVM log 判斷**。`Running Rex Nebular` 與 `section1.hag` 在**啟動時**就會出現，
    停在主選單的那次 log 跟成功那次一模一樣。
    （我原本把這兩個當判準寫進本檔，拿失敗那次的 log 一比就被推翻——
    **判準本身沒做正對照就等於沒有判準**。）
  - 可用的：**點擊前後各截一張，比對畫面雜湊**（主選單與遊戲畫面差異夠大），
    腳本裡不一樣就直接 exit，別錄完 115 秒才發現。
  - 最終驗收仍要**自己看畫面**：抽幾格用 Read 看，確認是遊戲場景不是選單。
- **[HARD] 配樂用原版真實音訊**（`SDL_AUDIODRIVER=disk` 錄原版 AdLib/MT-32），**不自產合成配樂**（`rulebook/93`）。公開只嵌**靜音 GIF ＋ 連 YouTube**。
- **這款只有 AdLib 可錄**（MT-32 做不到，理由見 §12）。使用者 2026-08-07 定案：推廣片用 AdLib 原版錄音。
- **音樂進點實測結果：前 30 秒是靜音**，之後穩定在 −37～−39 dB。錄音要送鍵推進（主選單 → 開始新遊戲 → 難度），取 30s 之後的片段。這是實測值，不是套 SCUMM 的結論。診斷方式：`volumedetect` 逐 15 秒掃描。

---

## 15. 需要先回報再確認

- 任何**超出「集中在中文路徑」的引擎改動**（動到 scene/player/sequence 的核心流程）。
- 公開散布含版權素材（遊戲本體、手冊掃描、MT-32 ROM、含原版配樂的影片）。
- `git push`、建 Release、對外發布。
- 判定「某批文字翻不了／某個功能做不到」之前——先 grep 自己的 `docs/`，答案常常是自己前幾天寫的。

## 16. 一律不要做

- 非 docker 編譯；系統 Python 直接 pip install。
- 把遊戲本體／手冊掃描／ROM／含版權配樂影片推**公開** repo。
- 動共用 docker 資源（見 §10）。
- 推廣片用自產合成配樂。
- 背景 sentinel 輪詢等檔。
- 把中文縮小去塞原版小字位（違反 `rulebook/81`）。

---

## 17. 硬規則速查

- [HARD] **必須 patch 引擎**（`font.cpp` 的 `& 0x7F`），但 patch 要**最小且集中**；出現「越修越多」先停下重想架構（`rulebook/41`）。
- [HARD] **不改遊戲資料檔**，走引擎端替換表；抽字先做 **round-trip diff = 0**。
- [HARD] **拉畫布 640×400，不縮字**；排版格與字模尺寸解耦。
- [HARD] 中文開關用**字型檔存在**，不用 `--language`；判 `chtEnabled()` 不判 `getLanguage()`。
- [HARD] 譯名以**當年中文手冊**為準（掃描圖需轉圖判讀）；統一譯名表所有 subagent 共用。
- [HARD] **限制級／輔導級兩套文字都要處理**，別只翻一套就宣稱完成。
- [HARD] 字形預設**倚天點陣字**，`SPCFONT` 必帶。
- [HARD] 公開 repo **patch-only**；`*.ROM`、遊戲資料、手冊掃描一律 gitignore。
- [HARD] **「許功蓋問題」有四型，任何碰譯文的逐 byte 操作都要 Big5-aware**。
  Big5 trail byte 落在 ASCII 可見範圍是家常便飯（「作」=A740、「一」=A440、「功」=A55C），
  **症狀一律是某幾個字悄悄變成別的字或整段消失，不崩潰也不報錯**，極易誤判成「字型缺字」查錯方向。
  1. **逐 byte 掃描**：`strchr`／`strstr`／`strtok`／手寫 `while (*p)` 在 trail byte 上誤中，
     把字從中間切開（`@`=0x40、`[`=0x5B、`\`=0x5C）。
  2. **結尾／前綴判斷**：`hasSuffix("s")` 這種判英文文法的，會被中文的 trail byte 誤中。
  3. **大小寫轉換**：`toUppercase()`／`toLowercase()`／`toupper()` 逐 byte 加減 0x20，
     trail byte 落在 `A-Z`(0x41–0x5A) 或 `a-z`(0x61–0x7A) 就變成另一個字。
     **實測 4357 筆譯文有 3619 筆（83%）中招**（「遊戲」→「鉍戲」、「關上」→「關已」）。
     順帶：`char` 是 signed，把 ≥0x80 的 lead byte 傳給 `toupper()` 本身就是 UB。
  4. **控制碼括號解析**：`DialogsNebular::show()` 逐 byte 找 `[` / `]` 判斷 `[title32]`
     這類指令。「也」=A4**5D**、「（」=A1**5D**、「久」=A4**5B** —— trail byte 剛好就是括號。
     `]` 那型最陰險：它落在 `else if (*srcP == ']')`，`commandFlag` 為 false 時什麼都不做，
     **那個 byte 就這樣消失**，畫面只剩一個孤兒 lead byte 畫成的半形怪符號。
     **實測 460/4357 行（10.6%）踩中**，而「也」「（」都是高頻字。
  **[HARD] 不要靠 grep 一型一型撞** —— 前三型都是看到畫面壞掉才回頭找，第四型是靠一張
  截圖上「這麼」後面一個怪符號才發現的。改用 `tools/big5_hazard_scan.py`：它把
  「引擎會拿哪些字元比對」跟「譯文裡有哪些字的 trail byte 撞上它」交叉起來，
  未防護且譯文實際會撞的組合會讓它 exit 1。確定不是譯文路徑（資源檔名、腳本指令行）
  就寫進 `tools/big5_hazard_allowlist.tsv` **並附理由**，不要調參數讓它閉嘴。
  掃描器本身也要做正對照（拆掉一處防護確認它會叫）—— 第一版 GUARD_HINTS 收了 `cht`，
  結果整段防護拆光它照樣說沒問題，因為同函式裡 `const bool chtOn = ...` 還在。
  修法：`ChtSupport` 的 `big5Strchr`／`big5ToUppercase`／`big5ToLowercase`／
  `big5CapitalizeFirst`／`big5EndsWithChar`。詳見 `docs/30-engine-design.md`。
- [HARD] **中文「沒顯示」要先分辨『沒畫』還是『畫了看不見』**，別急著查字型或譯文。
  在繪字迴圈加一行 debug 印出「code / 座標 / 顏色 / 字模有沒有」，一跑就分岔：
  - **沒畫** → 查譯文 key、字型缺字、繪字條件。
  - **畫了看不見** → 兩個已知原因：
    1. **顏色**：中文是 1bpp 只能挑一色，英文是 2bpp 用 `_fontColors[1..3]` 三色階。
       原本固定用 `[1]`，在難度選擇畫面（`resetGamePalette(18,10)` 換過盤）那是暗色。
       修法 `Font::pickInkColor()`：取三色裡亮度最高的（BT.601 權重，這款字常是綠或黃，
       用平均值會挑錯）。
    2. **被清掉**：文字層的 dirty 清除假設「scene 區的文字每幀重畫」。那對遊戲對白成立，
       對 `GameDialog`（全螢幕對話框，只在 `_redrawFlag` 時重畫）不成立 ——
       畫一次、下一幀被背景 dirty 清掉、再也沒人補回來。修法：中文啟用時該迴圈每幀重畫。
  **診斷關鍵是數量**：難度畫面印出「21 個字」，剛好等於標題+三個選項的字數總和 ——
  「剛好一輪」就說明它只畫了一次，問題在保存不在繪製。
- [HARD] 引擎行為斷言以**原始碼／實機當 oracle**，不憑記憶（本檔每條技術事實都附了檔名行號，新增條目照辦）。
- [HARD] 包驗收要**同時**比中文資料 md5 **與引擎指紋**。
- [HARD] configure 偵測不到函式庫只會**安靜關掉選項**，收尾要反查 `config.mk`。
- [HARD] 防呆／檢查腳本寫完**做正對照**（餵必定違反的輸入確認它會叫）。
- [HARD] README 交付必附開頭引言，別等使用者提醒。
- [HARD] **查詢回空 ≠ 不存在**；下「沒有／不存在」結論前先做正對照。
- [雷] `pkill -f` 會殺掉自己那行 shell，用 `pkill -x`。

---

## 18. 開工檢查清單

1. [ ] 解壓遊戲到 `game/`，`scummvm --list-games` 確認落在哪一筆 detection entry。
2. [ ] 建 docker image；自編 ScummVM（pristine）跑起來、截一張英文原版圖當對照組。
3. [ ] 寫抽字工具：`QUOTES.DAT` / `VOCAB.DAT` / `MESSAGES.DAT`（FAB 解壓）/ `*.TXR` /
   **`*.AA` 動畫內嵌訊息**（六個來源，見 §4.1）→ **round-trip diff = 0**。
   抽完**不要**直接相信「跑完沒報錯」：拿畫面上看得到的字反過來問「它從哪個來源來」，
   說不出來的就是還有第七個來源。（`.AA` 那一包就是這樣才被發現的，代價是九個角色名從沒進過翻譯流程。）
4. [ ] 統計字數（各來源則數）→ 寫進 `docs/00-scope.md`，README 的「N 則對白」由此而來。
5. [ ] 判讀完整本中文手冊 → `docs/20-glossary.md` 統一譯名表。
6. [ ] 再跑一輪網路資料蒐集（§6），補 `docs/10-references.md`。
7. [ ] 引擎改造：畫布 640×400 → Big5 繪字路徑 → 替換表查詢 → 字型檔開關 → 組句語序。**每一步各截一張圖**。
8. [ ] 烘 `rex_big5.fnt`（倚天，含 SPCFONT）。
9. [ ] 試譯一批給使用者看品質，確認風格後才 fan-out 全量。
10. [ ] 合併驗證 → 譯名一致性掃描 → 非 Big5 字 corrections → 重烘字型。
11. [ ] headless 全場景截圖驗收（含限制級／輔導級兩套）。
12. [ ] `dist-all/` 三平台打包 ＋ leak-scan ＋ 引擎指紋。
13. [ ] **[HARD] README（含開頭引言）**；（選）宣傳片、dev-setup 接續包。
14. [ ] 公開 repo 只推 patch-only。

---

## 19. 回應檢查

繁體中文；結論／風險／TODO 明確；無撞碼；未違反 patch 範圍與 patch-only 硬規則；引擎行為斷言附**檔名行號或實機截圖**而非記憶。

---

*建立 2026-08-06。技術事實出處：ScummVM 2.8.0 `engines/mads/`（font.cpp / game.cpp / scene.cpp / screen.h / font.h / detection_tables.h / nebular/game_nebular.cpp）。譯名出處：`DDSC-J-00084` 中文手冊掃描判讀。*
