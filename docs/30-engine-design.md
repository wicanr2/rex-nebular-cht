# 引擎中文路徑設計（MADS）

> CLAUDE.md §3 要求「最小且集中的 patch」，§4.1 要求「組句先寫設計文件再動手」。這是那份文件。
> 全部斷言附 ScummVM 2.8.0 的檔名行號，來源樹：`engines/mads/`。

## 1. 為什麼 patch 得起來——三個咽喉點都很窄

先做完整性盤點，再談改法。三條路徑各只有一個入口：

| 路徑 | 咽喉點 | 呼叫端數量 | 意義 |
|---|---|---|---|
| **繪字** | `Font::writeString()`（font.cpp:147） | **8 個**（messages.cpp:566、dialogs.cpp:364、user_interface.cpp ×5、dialogs_nebular.cpp:472） | 改這一支，全遊戲的字都會走中文路徑 |
| **排版寬度** | `Font::getWidth()`（font.cpp:222） | **100 個** | 呼叫端不用動——只要 `getWidth` 認得雙位元組，100 處排版計算自動正確 |
| **送畫面** | `Screen::update()`（screen.cpp:566） | 1 個（`Graphics::Screen::update()` 是 virtual） | 要拉畫布的話，唯一要改的地方 |

`getWidth` 那 100 個呼叫端是這個設計最大的利多：**排版是算出來的不是寫死的**，
所以中文只要寬度算對，換行、置中、對話框大小全部自動跟上。

## 2. 改動清單（最小集合）

### 新增檔案（中文邏輯集中在這裡）

| 檔案 | 職責 |
|---|---|
| `mads/cht_font.h/.cpp` | 載入 `rex_big5.fnt`（Big5 點陣字庫），提供 `drawBig5Char(surface, x, y, code, color)` |
| `mads/cht_text.h/.cpp` | 載入 `rex_cht.tsv` 替換表；提供 `chtEnabled()`、`quote(idx)`、`message(id)`、`vocab(idx)` |

### 既有檔的 hook 點（每一個都要說得出「為什麼非改不可」）

| 檔案 | 改什麼 | 為什麼非改不可 |
|---|---|---|
| `font.cpp:180` | `char theChar = (*text++) & 0x7F;` → 先判 Big5 lead byte（`>= 0xA1`），是就取兩個 byte 畫中文字模 | **這是整個專案的根本理由**：不改，任何中文位元組都會被折成 ASCII |
| `font.cpp:222` | `getWidth()` 同樣認雙位元組，中文寬度 = 字模寬 | 不改則 100 處排版全部算錯，換行與置中會爆 |
| `game.cpp:346/368` | `loadQuotes()` / `getMessage()` 回傳前查替換表 | 對白與旁白的來源 |
| `scene.cpp:257` | `loadVocabStrings()` 回傳前查替換表 | 指令列與物品名的來源 |
| `staticres.cpp` | `kArticleList`、`kWalkToStr`、`kLookAroundStr` 等加中文分支 | 引擎硬寫，不走資源，漏了指令列就是中英夾雜 |
| `mads.cpp:169` | `loadChtResources()` 要放在這裡（見下方 §5 init 順序） | 中文開關 |

## 3. 替換表以 index／id 為 key，不用英文原文

`rex_cht.tsv` 格式：`來源:key <TAB> 中文譯文`，例：

```
quote:301      「這裡是個小型地下聚落，住的全是自稱『守護者』的女性。」
msg:2.0        [title32][sentence]
vocab:38       望遠鏡
```

理由：原文有大量重複（`ON`/`OFF`/`STILL` 在 QUOTES 裡各出現兩次，`game.h:169` 的 `getQuote(index)`
用的就是 index），用內容當 key 會撞。詳見 `docs/00-scope.md`。

## 4-final. [已實作 2026-08-06] 中文走「文字層」——這才是正解，下面 §4 是走到這裡的過程

### 症狀

第一版做完，中文能顯示了，但**字大得離譜**。量出來：中文 16×15 的字模畫在 320 空間，
被 `Screen::update()` 連同底圖一起 2× 放大 → 螢幕上是 **32×30 實際像素**；
而英文原本 7px 放大後只有 14px。中文是英文的兩倍多。

### 根因（第一性）

放大發生在「送畫面」那一層，它不分辨像素是底圖還是文字。**底圖需要放大**（原生 320×200 的
pixel art），**文字不需要**（點陣字本來就是為某個尺寸手工調的）。把兩者綁在同一次放大裡，
就一定會有一方是錯的。

### 解法：文字層（`Screen::_chtLayer`）

| | 走哪一層 | 解析度 |
|---|---|---|
| 底圖、sprite、UI 面板 | 320×200 surface → update() 時 2× nearest 放大 | 邏輯 320，顯示 640 |
| **中文字** | **直接畫進 640×400 的 `_chtLayer`，1:1 不放大** | 顯示 640 |
| 英文字 | 照原本路徑畫進 320 surface（跟著放大） | 邏輯 320，顯示 640 |

合成在 `Screen::copyRectScaled()`：先放大底圖，再把文字層非 0 的像素疊上去。

**排版度量要回報「320 空間的等效值」**：`Font::getWidth()` 對中文回 `glyphWidth / 2 = 8`，
`getHeight()` 完全不動（維持 `_maxHeight`）。因為顯示上 16×15 ≒ 320 空間的 8×7.5，
與原版英文字尺寸相當 —— **於是換行、置中、對話框大小、UI 格線全部維持原版，一行都不用改**。

### 意外收穫：先前為了塞中文做的 UI 佈局改造，全部撤回了

`user_interface.cpp` 的 `bounds.setHeight(8)` 在顯示層是 16px，而中文字模剛好 15px。
原版「5 列 2 欄、格 32×8」的佈局重新變得剛好，verb 也不必縮成單字。
**改對了架構之後，引擎改動反而變少**——這是「越修越多就是架構選錯」的正面例證（`rulebook/41`）。

### [雷] 文字層的清除：dirty 驅動只能用在 scene 區

文字層需要在「背景把字蓋掉」時清除，否則舊字永遠留在畫面上。第一版用
「dirty rect 就清文字層」，結果 **UI 文字整片消失**：

- **scene 區**可以這樣做 —— kernel message 每幀都重繪，清了立刻補回來。
- **UI 區不行** —— 物品旋轉動畫每幀都讓整個 UI 變 dirty，但 verb 列與物品名
  只在內容變動時才重畫，一起清掉就再也補不回來。

修法：自動清除限縮在 `y < MADS_SCENE_HEIGHT`；UI 區改由 `writeString` 在畫每個字之前
清自己那一格（`chtClear` + `chtTouch`）。`_chtTouched` 的用途就是分辨
「這塊 dirty 是文字自己重畫」還是「背景把文字蓋掉了」。

> **待辦**：UI 文字「消失」而非「改變」時（例如物品被拿走、該格變空），
> MADS 只畫背景不呼叫 `writeString`，文字層會殘留。目前未觸發，
> 若出現殘留就在 `UserInterface::refresh()` / 場景切換時整片清 UI 區。

### [雷·必看] 文字層不可以拿「顏色 0」當透明——要另開遮罩

**症狀**：一行中文裡有幾個字不見了，露出底圖，看起來像「被黑塊蓋住」。位置固定，
換場景還是那幾個字。整屏合成、檢查缺字、比對 `getWidth`／`xEnd` 全都排除不掉。

**根因（第一性）**：文字層是 8-bit 調色盤索引，我拿「像素值 0」當透明判斷。
但 **0 是合法的顏色索引**，而 MADS 的文字色來自 `Font::_fontColors[1]`，
其值由呼叫端決定（`TextDisplayList::draw()` 會 `setColors(0xFF, td._color1, ...)`），
**真的會是 0**。於是那些字被畫成 0 → 合成時判定為透明 → 等於沒畫。

英文路徑不受影響，因為它直接寫進 320 的 surface，那裡 0 就是單純的顏色。

**修法**：另開一張同尺寸的 `_chtMask`，寫字時 `mask[x] = 1`，合成時看 mask 而不是看顏色值。
`chtClear()` 要同時清兩張。

**通則**：任何「用某個特殊值代表沒有資料」的設計，先問「這個值是不是也是合法資料」。
是的話就要另外存在別的地方——這跟 `-1` 當錯誤碼、`0` 當空指標是同一類問題。

### [雷·必看] 逐 byte 的 `strchr` 會在 Big5 trail byte 上誤中——「許功蓋問題」的第二型

**症狀**：片尾製作名單顯示成「製宏P設計」（應為「製作與設計」）、「執行製坐H」（應為「執行製作人」）。
特徵是**某幾個字變成別的字，而且冒出 ASCII 字母**。

**根因**：`menu_views.cpp` 的 `TextView::processLines()` 直接掃整行找分隔字元：

```cpp
char *centerP = strchr(_currentLine, '@');   // '@' = 0x40，置中標記
char *cStart  = strchr(_currentLine, '[');   // '[' = 0x5B，指令開始
```

而 **Big5 的 trail byte 落在這些值上是家常便飯**：

| 字 | Big5 | trail | 撞到 |
|---|---|---|---|
| 作 | `A7 40` | 0x40 | `@` |
| 一 | `A4 40` | 0x40 | `@` |
| 乩 | `A5 5B` | 0x5B | `[` |

`strchr` 在中文字的第二個位元組上誤中 → `*centerP = '\0'` 把字從中間切開 → 後半段被當成另一個欄位搬移。

這與 SCUMM/AGI 那邊著名的**「許功蓋問題」同型**（那邊是 trail byte 撞 `\` = 0x5C，
`TextMgr::stringPrintf()` 遇 `\` 就跳過，吃掉半個中文字）。差別只在撞到的是哪個 ASCII 字元。

**修法**：`chtStrchr()` —— 掃描時遇 lead byte（≥ 0xA1）就整個跳兩格，不看它的 trail。
只在中文啟用時生效，英文路徑完全不受影響。

**[HARD] 通則**：**任何對譯文做逐 byte 掃描的地方都要 Big5-aware**。
不只 `strchr`，`strstr`、`strtok`、手寫的 `while (*p)` 迴圈都算。

### [雷·必看] 第三型：大小寫轉換——影響面比 `strchr` 大得多

**這是後來才補查到的，而且是三型裡影響最廣的一型。**

`Common::String::toUppercase()` / `toLowercase()` 是逐 byte 跑 `toupper`/`tolower`。
Big5 的 trail byte 大量落在 `A-Z`(0x41–0x5A) 與 `a-z`(0x61–0x7A)——
被加減 0x20 之後，**字直接變成另一個字**：

```
「遊戲」  a9 43 c0 b8 → toLowercase → 「鉍戲」
「關上」  c3 f6 a4 57 → toLowercase → 「關已」
「通風口」b3 71 ad b7 a4 66 → toUppercase → 「被風了」
```

實測本專案：**4357 筆譯文有 3619 筆（83%）含會被改掉的 trail byte**；
單看 vocab 是 845 / 1193（71%）。

真正會踩到的路徑是 `DialogsNebular::getVocab()`（`nebular/dialogs_nebular.cpp:195`）：

```cpp
Common::String vocab = _vm->_game->_scene.getVocab(vocabId);   // ← 譯文
switch (_capitalizationMode) {
case kUppercase:  vocab.toUppercase();   // ← 整串逐 byte
case kLowercase:  vocab.toLowercase();
```

而 `_capitalizationMode` **預設就是 `kUppercase`**（`dialogs_nebular.h:41`，`.cpp:56` 每次重設），
由對話文字裡 `[VERB]` / `[Verb]` / `[verb]` 佔位符的大小寫決定。
換句話說：**任何含 vocab 佔位符的對話框，中文詞彙都會被改掉。**

同一型的還有兩個變種：

- **`hasSuffix("s")` 判英文複數**（`dialogs_nebular.cpp:236`）。中文譯文的最後一個位元組是
  trail byte，可能剛好是 `'s'`(0x73)——「快存」= `A7 D6 A6 73`——於是被判成複數，挑錯句型。
- **`toupper(vocab[0])` 判母音決定 a/an**（`:245`）。中文不需要冠詞，而且 `char` 是 **signed**，
  把 ≥0x80 的 lead byte 傳給 `toupper()` 本身就是未定義行為。

修法在 `ChtSupport`（`cht.h`/`cht.cpp`）：`big5ToUppercase` / `big5ToLowercase` /
`big5CapitalizeFirst` / `big5EndsWithChar` / `big5StartsWide`。核心是逐**字元**走而不是逐 byte，
雙位元組字整個跳過（中文沒有大小寫），ASCII 照常轉換。

驗證用全量譯文對照：修正後 8714 次轉換中，中文 byte 全部不變、ASCII 仍正確轉換
（`[title26]` → `[TITLE26]` 這種佔位符功能沒壞）；同一批資料餵給原本的逐 byte 版，
**6154 次會改壞**。

### [雷·必看] 第四型：`[` / `]` 控制碼括號解析——`]` 那型會讓字「消失」而不是「變樣」

`MESSAGES.DAT` 的譯文帶控制碼（`[title32][sentence]`、`[noun1]`、`[center]`），
`DialogsNebular::show()`（`nebular/dialogs_nebular.cpp:42`）逐 byte 走一遍去找括號：

```cpp
while (srcP < srcLine.c_str() + srcLine.size()) {
    if (*srcP == '[')       { commandText = ""; commandFlag = true; }
    else if (*srcP == ']')  { /* 執行指令 */ commandFlag = false; }
    else if (commandFlag)   { commandText += *srcP; }
    else                    { dialogText += *srcP; }
    ++srcP;
}
```

撞上的字：

| 字 | Big5 | trail byte | 後果 |
|---|---|---|---|
| 久 | A4 **5B** | `[` | lead byte 落單，之後整行被吞進 commandText |
| 也 | A4 **5D** | `]` | lead byte 落單，trail byte **直接消失** |
| （ | A1 **5D** | `]` | 同上，而且這是全形標點、到處都是 |
| 包 | A5 **5D** | `]` | 同上 |

`]` 比 `[` 難查：它落在 `else if (*srcP == ']')` 分支，`commandFlag` 是 false 時
**什麼事都不做** —— 沒有例外、沒有警告，那個 byte 就是沒被加進 `dialogText`。
畫面上看到的是一個孤兒 lead byte 被當成半形字畫出來的怪符號。

實測影響 **460 / 4357 行（10.6%）**，共 537 個字。實際被抓到的那一幕：

```
譯文  這台機器擺在這裡這麼久了，\n你到現在還是搞不懂「投入硬幣」是什麼意思。
畫面  這台機器擺在這裡這麼⁋　你到現在還是搞不懂「投入硬幣」是什麼意思。
                          ↑ 「久了，」三個字沒了，只剩一個怪符號
```

下一行為什麼正常？因為迴圈每處理完一行就重置 `commandFlag`。
**症狀只影響「含受害字的那一行」，同一個對話框的其他行完全正常** —— 這讓它看起來
更像「翻譯打錯字」而不是引擎問題。

### 盤點方式：不要一型一型撞

前三型都是**看到畫面壞掉才回頭找**，第四型是靠一張截圖上一個怪符號才發現的。
手寫 grep 的問題是：要先想到該 grep 什麼字元，而「`]` 也是 trail byte」這件事
不會自己浮現。改用交叉比對：

```bash
python3 tools/big5_hazard_scan.py engines/mads cht-data/rex_cht.tsv
```

它做三件事：

1. 掃引擎原始碼，抓出所有「拿單一字元跟某個 byte 比對」的位置
   （`== 'x'`、`strchr`、`hasSuffix`、`hasPrefix`、`findFirstOf`…）。
2. **只留下字元值落在 Big5 trail byte 範圍（0x40–0x7E）的** ——
   `' '`(0x20)、`'\n'`(0x0A)、`'\0'` 自動排除，不用人腦判斷哪個安全。
3. 掃譯文算出每個危險字元**實際**會撞到哪些字、幾行。
   有譯文佐證的才是真風險；沒有的列為潛在風險（換一批譯文就可能中）。

未防護 × 譯文實際會撞 → exit 1。確定那個字串不可能是譯文（資源檔名、腳本指令行、
debug console 輸入都是純 ASCII），寫進 `tools/big5_hazard_allowlist.tsv` **並附理由**。

> **[HARD] 掃描器自己也要做正對照。** 第一版的 `GUARD_HINTS` 收了 `cht` 這個字樣，
> 我把 `dialogs_nebular.cpp` 的 Big5 防護整段拆掉去測，它照樣回報「✓ 沒問題」——
> 因為同一個函式裡 `const bool chtOn = _vm->_cht && ...` 這行還在偵測窗內。
> 「附近提到中文化」不等於「這個迴圈有跳過雙位元組字」。收緊成只認 `0xA1` 比較
> 或 `ChtSupport::big5*` 呼叫之後，正對照才過（exit 1 並精確指出 `[` 和 `]` 兩處）。

補充：`GUARD_WINDOW` 一開始設 12 行，結果同一個迴圈裡 `'['` 判成已防護、四行之後的
`']'` 判成未防護 —— 防護寫在迴圈開頭，離 `']'` 有 13 行。一個迴圈罩得住的範圍比
12 行大，改成 30。

手動盤點仍可當補充（要掃全樹，本專案最嚴重那處在 `nebular/` 子目錄）：

```bash
grep -rn 'strchr\|strrchr\|strstr\|strtok\|strpbrk' --include=*.cpp --include=*.h engines/mads/
grep -rn 'toupper\|tolower\|toUppercase\|toLowercase' --include=*.cpp --include=*.h engines/mads/
grep -rn 'findFirstOf\|hasSuffix\|hasPrefix\|\.contains(' --include=*.cpp engines/mads/
```

凡是經過 `getVocab()` / `getQuote()` / `getMessage()` 的都要處理。
**這類 bug 不會崩潰、不會報錯，只會讓某幾個字悄悄變成別的字或整段消失**——而且只在
特定文字上出現，所以很容易被當成「字型缺字」或「翻譯打錯」而查錯方向。

**診斷方式值得記**：推論了三輪都沒中（缺字？截斷？dirty 範圍？），
最後是在 `writeString` 加一行 `debug(1, ...)` 印出 `pt / ofs / width / xEnd / surface 尺寸`，
一跑就看出「文字有畫、參數也對」，才把矛頭轉向合成端。
**引擎行為的斷言要用實測，不要用推論鏈**。

---

## 4. [過程紀錄] 畫布尺寸：**拉 640×400**——UI 格線是寫死的 8px，逼著非拉不可

先講結論的證據，這條原本是「等截圖再決定」，證據到手後沒有選擇空間：

```cpp
// engines/mads/user_interface.cpp  UserInterface::getBounds()
case CAT_COMMAND:                     // 指令表（畫面左下的 verb 列）
    leftStart = 2; yOffset = 3; widthAmt = 32;   // 5 列 × N 欄
...
bounds.top = heightMultiplier * 8 + yOffset;
bounds.setHeight(8);                  // ← 格高寫死 8 像素
```

- **verb 格 = 32×8 px**，物品欄格 = 69×8 px。原版英文字高 7–8px，剛好。
- 倚天最小的原生尺寸是 **16×15**，高度是格子的兩倍 → **直接塞會上下相撞、字被裁掉**。
- 而 `rulebook/81` [HARD] 禁止把中文縮到 8px 去塞原字位（那高度連「藏」「醫」都畫不出來）。

兩個限制夾在一起，就是 `rulebook/81` 講的「換維度」：**不是二選一，是把畫布拉大**。
實機截圖（`out/01-pristine-en-ingame.png`）量到的對話框（遊戲座標 176×72，字高約 7px）也印證：
對話框大小是 `getWidth()` 算出來的會自動長大，**但 UI 格線不會**——它是常數。

### 採用方案：scene 2× 放大，UI 與文字原生高解

1. `initGraphics(640, 400)`（mads.cpp:169）。
2. MADS 內部 `Screen`／scene surface **維持 320×200 不動** → 所有 sprite、hotspot、動畫、
   場景邏輯一行都不用改（這是把改動關在門內的關鍵）。
3. 覆寫 `Screen::update()`（screen.cpp:566，`Graphics::Screen::update()` 是 virtual）：
   把 320×200 內容 **2× nearest 放大**進 640×400 的 buffer 再送 `g_system`。
   底圖是 pixel art，**不可用雙線性**。
4. **文字與 UI 走高解路徑**：verb 格／物品欄／對話框的座標 ×2（32×8 → 64×16），
   中文 16×15 畫在放大後的 buffer 上。一格 64px 寬 = **4 個中文字**，夠放「走到」「拆解」。
5. 滑鼠命中區同步 ×2（`screen.cpp` 的 `ScreenObjects` hit-test），漏了會變成「點得到看不到」。

### 為什麼不選另外兩條

| 方案 | 否決理由 |
|---|---|
| 320×200 + 12×12 中文 | 12px 仍 > 8px 格高，一樣撞；且倚天沒有 12 點原生字，得從 15 縮 → 糊 |
| 改 UI 佈局常數（格高 8→16，列數 5→3） | 介面區總高只有約 44px（200 − `MADS_SCENE_HEIGHT` 156），5 列 ×16px = 80px 放不下；砍列數等於砍掉玩家能用的指令 |

### 這一步的驗證（做完立刻檢查，別堆到最後）

- 只做第 1–3 步、**先不加中文**：畫面應該跟 pristine 一模一樣，只是解析度變兩倍。
  這一步過不了就別往下做——問題出在放大管線，不是中文。
- 檢查 dirty rect：MADS 用 `copyRectToScreen(bounds)`（screen.cpp:231）局部更新，
  放大後座標要一起換算，否則會出現「畫面殘影／只更新一半」。

## 4b. 原本的待決紀錄（保留，說明決策怎麼來的）

CLAUDE.md §4.3 依 `rulebook/81` 預設「拉畫布 640×400」。實際盤點後有兩條路，成本差很多：

| | A. 不拉畫布（320×200 + 16×15 中文） | B. 拉畫布（640×400 + 16×16 或 24×24） |
|---|---|---|
| 改動 | 只改 `Font` 兩支函式 | 另加：`initGraphics(640,400)`、覆寫 `Screen::update()` 做 2× nearest 放大、**中文字要畫在放大後的 buffer** |
| 中文行寬 | 320 ÷ 16 = **20 字/行** | 640 ÷ 16 = 40 字/行（或 24px 時 26 字/行） |
| 風險 | 中文比原版英文字（高約 8–10px）大一倍，對話框可能塞不下 | **文字得脫離 320 surface 改走 overlay**，而 MADS 的文字是畫進 surface 後靠 dirty rect 保留的，不一定每幀重繪 → overlay 可能閃爍或消失 |
| 底圖 | 原樣 | nearest 2× 放大，銳利 |

**B 的關鍵未知**：MADS 的對話框文字是「畫一次留在 surface」還是「每幀重繪」。
是前者的話，overlay 方案要自己追蹤失效區域，複雜度會跳一級——那正是 CLAUDE.md §3
說的「越修越多」的前兆。

**判斷準則（等 pristine 截圖到手就能決定）**：
1. 量原版對話框的實際像素尺寸與英文字高。
2. 若對話框高度容得下 15px 中文 ×（原文行數 +1），走 **A**（改動小、風險低，先出一個能玩的版本）。
3. 若明顯塞不下，才走 **B**，並且先做一個「只放大不加中文」的最小驗證，確認 dirty rect 不會出問題。

> 這條**不是**在推翻 rulebook 81 的「不要縮字」——A 案用的是 16×15 原生尺寸的倚天字，
> 沒有縮字。rulebook 81 反對的是把中文縮到 8px 塞原字位，A 案不做那件事。

## 5. 中文開關與 init 順序

- 開關＝**遊戲目錄有沒有 `rex_big5.fnt` + `rex_cht.tsv`**，不是 `--language`
  （`detection_tables.h` 全部 `EN_ANY`，設非英文語言會改變 detector 行為）。
- 引擎裡一律判 `chtEnabled()`，**不判 `getLanguage()`**。
- `loadChtResources()` 必須在**任何會「在建構子裡抓一次字串」的物件之前**執行
  （LSL1 的 `SystemUI` 就是踩這個坑）。MADS 這邊要確認 `Font::init()`（mads.cpp）
  與 UI 物件的建構順序。

## 6. 組句與語序（`kArticleList`）

`staticres.cpp` 的 `kArticleList = {nullptr, "with", "to", "at", "from", "on", "in", "under", "behind"}`
把「動詞＋名詞＋介係詞＋名詞」拼成指令列。

**好消息**：中文的「動詞＋受詞」語序與英文一致，`Walk to Escape Hatch` →「走到 逃生艙」直接可用。
**要處理的只有介係詞句**：`Throw Log at Bulkhead` →「丟 船長日誌 向 艙壁」。
v1 先照 `docs/20-glossary.md` 的介係詞對照直譯（用／到／向／從／在…上／在…裡／在…下／在…後），
實機看過再調。**不做語序重排**——那需要動 `action.cpp` 的組句邏輯，超出「集中在中文路徑」的範圍。

## 7. 驗證順序（每步一張截圖）

1. pristine 英文截圖（對照組）→ 量對話框尺寸 → 定畫布方案
2. 只換字型、不換文字：畫面應該完全沒變（證明 `Font` 改動沒破壞英文路徑）
3. 只翻 VOCAB：指令列變中文、對白仍英文（證明替換表接得上、排版寬度算得對）
4. 全量翻譯 → 全場景截圖驗收（含限制級／輔導級兩套）
