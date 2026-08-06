# 統一譯名表（錯體奇航）

> **所有翻譯 subagent 動筆前必須先讀這一份。** 譯名一經定案不得中途改——名詞會出現在
> 「動詞＋名詞」組成的指令列裡，改一個要重掃全部譯文。
> 來源標記：**手冊** = 當年中文手冊 `DDSC-J-00084` 判讀所得（一手，優先於一切）；
> **定案** = 本專案自訂並已鎖定；**待定** = 尚未使用，用到再補進來。

## 1. 專有名詞（手冊一手）

| 英文 | 中文 | 來源 |
|---|---|---|
| Rex Nebular and the Cosmic Gender Bender | 錯體奇航 | 手冊 |
| Rex Nebular | 雷克斯‧尼布勒（內文簡稱「雷克斯」） | 手冊 |
| Rex 的太空船 *Slippery Pig* / the Pig | **油豬號** | 手冊（300dpi 複核確認）＋遊戲文字交叉印證 |
| Keepers | 守護者 | 定案 |
| Log | 船長日誌 | 手冊 |
| Rebreather | 水中呼吸器 | 手冊 |
| Binoculars | 望遠鏡 | 手冊 |
| Escape Hatch | 逃生艙 | 手冊 |
| Bulkhead | 艙壁 | 手冊 |
| Refrigerator | 冰箱 | 手冊 |
| Burger | 漢堡 | 手冊 |
| View-screen | 螢幕 | 手冊 |
| Video Game / Computer Game | 電動玩具 | 手冊 |
| Command Chair | 駕駛椅 | 定案（手冊作「電動的椅子」，過長） |

## 2. 指令動詞（VOCAB.DAT 0–12 與散落各處的動詞）

指令列會組成「動詞＋名詞」或「動詞＋名詞＋介係詞＋名詞」，中文語序與英文一致，直接對譯即可。

| 英文 | 中文 | 英文 | 中文 |
|---|---|---|---|
| look | 觀看（手冊） | walk to | 走到 |
| take | 拿取 | swim to | 游到 |
| push | 推 | climb up / down / through | 爬上 / 爬下 / 爬過 |
| pull | 拉 | dive into | 潛入 |
| open | 打開 | disassemble | 拆解 |
| close | 關上 | attach | 接上 |
| put | 放置 | break | 弄壞 |
| give | 給 | burn | 燒 |
| throw | 丟 | cut | 切 |
| talk to | 交談 | eat / drink | 吃 / 喝 |
| activate | 啟動 | eject | 彈出 |
| admire | 欣賞 | empty | 倒空 |
| cast | 拋出 | dampen | 弄濕 |
| Look Around | 環視（手冊） | Use | 使用 |

**介係詞**（`staticres.cpp` 的 `kArticleList`，用來拼指令列）：

| with | to | at | from | on | in | under | behind |
|---|---|---|---|---|---|---|---|
| 用 | 到 | 向 | 從 | 在…上 | 在…裡 | 在…下 | 在…後 |

## 3. 選單與系統 UI（QUOTES.DAT 1–48，對照手冊）

| 英文 | 中文 | 來源 |
|---|---|---|
| DONE / CANCEL / CLEAR | 完成 / 取消 / 洗掉 | 手冊（Clear＝把進度洗掉） |
| SAVE / RESTORE | 儲存 / 載入 | 手冊 |
| YES / NO / OK | 是 / 否 / 確定 | 定案 |
| REX NEBULAR GAME MENU | 錯體奇航 遊戲功能選單 | 手冊 |
| Save Game | 儲存進度 | 手冊 |
| Restore Game | 載入進度 | 手冊 |
| Game Play Options / Gameplay Options | 其它功能 | 手冊 |
| Resume Current Game | 回到目前的遊戲之中 | 手冊 |
| Exit From Game | 回到遊戲主選單 | 手冊 |
| REX NEBULAR GAME OPTIONS MENU | 錯體奇航 其它功能 | 手冊 |
| Music is @ | 音樂開關 @ | 手冊 |
| Sound is @ | 音效開關 @ | 手冊 |
| Interface is @ | 操作介面 @ | 手冊 |
| Inventory is @ | 物品顯示 @ | 手冊 |
| Text Window is @ | 指令與物品視窗 @ | 手冊 |
| Screen Fade is @ | 畫面切換 @ | 手冊 |
| Storyline is @ | 故事線 @ | 手冊 |
| ON / OFF | 開 / 關 | 定案 |
| STANDARD / EASY | 標準型 / 簡易型 | 手冊 |
| SPINNING / STILL | 旋轉型 / 靜止型 | 手冊 |
| ANIMATED | 活動型 | 手冊 |
| SMOOTH / MEDIUM / FAST | 平滑型 / 中等型 / 快速型 | 手冊 |
| NAUGHTY / NICE | 限制級 / 輔導級 | 手冊 |
| Locked-Nice | 乖寶寶級 | 手冊 |
| DESCRIBE GAME TO BE SAVED | 為這個進度取個名字 | 定案 |
| SELECT GAME TO BE RESTORED | 選擇要載入的進度 | 定案 |
| SELECT A DIFFICULTY LEVEL | 選擇難度 | 定案 |
| Novice - Easy | 新手 — 簡單 | 定案 |
| Advanced - Difficult | 進階 — 困難 | 定案 |
| Expert - Very Difficult | 專家 — 非常困難 | 定案 |
| Save / Restore Complete | 儲存完成 / 載入完成 | 定案 |
| Save / Restore Failed | 儲存失敗 / 載入失敗 | 定案 |
| (Empty) | （空的） | 定案 |
| Look Around | 環視 | 手冊 |

## 4. 主選單（開機畫面，手冊）

| 英文 | 中文 |
|---|---|
| Start a new game | 開始一個全新的遊戲 |
| Resume last game | 由上次離開之處繼續遊戲 |
| Watch Introduction | 觀賞動畫開幕篇 |
| Credit | 遊戲製作小組一覽 |
| Exit | 離開遊戲 |

> 主選單這幾行在遊戲裡是 **bitmap 美術圖**（`font.h:36`：Rex 的選單字串用圖不用字型），
> 要中文化得改圖，不在文字替換表的範圍內。

## 4b. 試譯批收斂後的定案（2026-08-06，第一次一致性掃描）

兩批試譯之間出現漂移，以下為**定案版本**，後續所有批次一律照用：

| 英文 | 定案中文 | 說明（為什麼選這個） |
|---|---|---|
| "DURAFAIL" CELLS | **勁掛電池** | 原文是 Duracell 的諧音惡搞，中文用「勁量→勁掛」接住這個梗。不要用直白的「故障電池」 |
| detonators | **雷管** | 爆破器材的正式名稱，比「引爆器」精確 |
| penlight | **筆型手電筒** | 與 `flashlight` 區分 |
| phone handset | **電話聽筒** | 不要用「話筒」 |
| phone cells | 電話電池 | 與勁掛電池是不同物品 |
| charge cases | 裝藥盒 | 與雷管、計時模組同屬爆破組件 |
| timer module / target module | 計時模組 / 瞄準模組 | — |
| shield modulator | 護盾調變器 | — |
| tape player | 錄音機 | `audio tape` = 錄音帶 |
| hyperdrive jump unit | 躍遷裝置 | hyperdrive 統一用「躍遷」 |
| hyperdrive shunt | 躍遷分流器 | 同上，不要另起「超空間」 |
| damage control (panel) | 損害管制（面板） | — |
| estrotoxin | 雌激素毒素 | 劇情關鍵物質 |
| men who came before | 先民 | 世界觀用語 |
| Cowplug VIII | 牛塞八號星 | 地名 |
| Great Bovine Reefs | 大牛角礁 | 地名 |
| Bageljuice IX | 貝果汁九號星 | 地名 |
| Goldenpipe Space Port | 黃金管太空港 | 地名 |
| Asteroid 80791-G | 小行星 80791-G | — |
| TWINKIFRUIT | 甜滋果 | — |
| Beezlebody's Novelty Shop | 別西怪玩具店 | — |
| Project KABLOOEY | 轟毀計畫 | — |
| Ihma Pyro | 艾瑪‧派羅 | 人名（教授） |
| Bicuspidor | 畢庫斯波多 | 曆法名 |
| manta ray | 鬼蝠魟 | 「蝠鱝」的「鱝」不在 Big5，不可用 |

## 4c. 第二輪收斂（2026-08-06，messages 01–06／quotes 01–02／vocab 01–02 完成後）

| 英文 | 定案中文 | 說明 |
|---|---|---|
| the Gender Bender（機器本身） | **錯體機** | 呼應片名「錯體奇航」。指片名時仍用《錯體奇航》 |
| transmorph | **變體人** | 有批次譯「變體者」，統一用「變體人」 |
| Bud（蜥腳龍盟友） | **巴德** | 與賓奇是不同角色 |
| Binky | 賓奇 | Bionic Hamsteroid = 仿生鼠獸 |
| Lolita | 蘿莉塔 | 雷克斯的舊情人 |
| Rectarian | 雷克塔人 | 原文疑似藏 rectal 諧音，中文接不住，音譯 |
| shaman / witchdoctor | 巫醫 | 同一角色的兩種說法 |
| cockpit | 駕駛艙 | 與 Command Chair =「駕駛椅」區分 |
| MLV | 磁浮車 | galactars = 銀河幣 |
| credit chip | 信用晶片 | — |
| teleporter / teleport device / transposition device | 傳送器 / 傳送裝置 / 移位裝置 | 三個不同英文詞，不可合併 |
| security card / office / panel | 保全卡 / 保全辦公室 / 保全面板 | security 家族統一「保全」 |
| gender scanner | 性別掃描器 | — |
| 'Crust' tube | 『痂膏』牌 | Crest 的惡搞，中文用「痂」接住「牙膏乾成結痂」 |
| "Gal" magazine | 《辣妹》 | 虛構成人雜誌，非真實商標 |
| commode / toilet | 馬桶 / 廁所 | 器具 vs 場所 |
| Cowplug VIII / Bageljuice IX | 牛塞八號星 / 貝果汁九號星 | — |
| Tikillya Earthrise | 提基拉地出 | Tequila Sunrise 的諧音哏 |

**未決（不要自己硬翻，遇到留原文並回報）**：`adsm`、`mtam`、`zink` — 查無語意，且在引擎互動邏輯裡零引用。
`throne`（牢房浴廁區）疑似「馬桶」的戲稱，待實機畫面確認。

**開發者除錯殘留**（`<Deleted: Estrotoxin>` 這種尖括號格式）：**維持英文原樣不譯**，玩家看不到。

**原作自帶的開發者彩蛋**（例如提到 Brian Reynolds、MicroProse 的 NOTE）：**照原樣直譯保留**。
「不拿真人開玩笑」那條紅線約束的是**我們新增的梗**，不是原作既有的致敬。

## 5. 譯名一致性紅線

- 人名地名一經定案不得出現第二種寫法（LSL1 實測：同一個姓氏跑出三種譯法，事後全域 replace 收斂）。
- 名詞譯文**不要加標點、不要加語氣詞**——它們會被塞進指令列。
- 中文譯名長度盡量 ≤ 原文顯示寬度的 1.5 倍；指令列空間有限。
