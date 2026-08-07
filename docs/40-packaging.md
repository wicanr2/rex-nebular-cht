# 三平台打包

Windows、macOS、Linux 三個包的引擎都由**同一份 patch** 套出來
（`workplace/patches/rex-cht-engine.patch`，基準 ScummVM v2.8.0），
中文資料都取自 `cht-data/`。兩者各自有可驗證的指紋，三平台必須一致。

| 平台 | 產物 | 怎麼編 | 驗收 |
|---|---|---|---|
| Windows | `rexnebular-cht-win64.zip` | docker mingw-w64 交叉編，SDL2 自原始碼編 | wine 實跑進遊戲截圖 |
| macOS | `.dmg` + `.tar.gz`（universal） | GitHub Actions `macos-14`，per-arch 各編一次 + lipo | CI 內斷言雙弧、無殘留路徑 |
| Linux | `.AppImage` + patch zip | 本機 docker | Xvfb 實跑進遊戲截圖 |

## 引擎指紋

`workplace/tools/engine_fingerprint.py` — `sha256(engines/mads/**/*.cpp,*.h 依路徑排序後串接)` 取前 12 碼。
目前值 **`b5e9742121ea`**（124 個檔）。

為什麼需要它：包驗收如果只比中文資料的 md5，對「只改引擎、資料沒動」是完全的盲區——
資料全對、包裡卻裝著修正前的引擎，檢查照樣全綠。

> **舊指紋 `bc70b3a26fd0` 作廢。** 它記在早期的 `ENGINE.txt` 裡，宣稱的演算法與現在這支相同，
> 但**用它自己記載的演算法重現不出來**（實得 `b5e9742121ea`），而產生它的腳本沒有留下。
> 六種合理變體（含檔名、不遞迴、只 .cpp、只 .h、絕對路徑排序）全部試過都不命中。
> 指紋的價值在於可重現，重現不了的指紋等於沒有——所以換成這支可重跑、可 `--expect` 比對的版本。

## Windows：六條編碼規則

每一條在 Linux 開發機上都測不出來，到玩家端才爆。由 `tools/package_windows.py` 寫入、
`tools/check_windows_zip.py` 逐條驗。

1. 包內檔名一律 ASCII，且每個 entry 強制帶 UTF-8 旗標（bit 11）
2. `.bat` 換行 CRLF
3. `.bat` 內容純 ASCII（中文提示放 README）
4. `.bat` 帶 `if errorlevel 1` + `pause`
5. README 存 UTF-8 with BOM
6. 附靜態 `scummvm.ini` 鎖 `gui_language=en`，設定不污染玩家全域 ScummVM

### [雷] Python 的 `zipfile` 會把 UTF-8 旗標丟掉

直接寫 `zi.flag_bits |= 0x800` **沒有用**。`ZipFile.writestr()` 內部把 flag_bits 歸零再重算，
設好的值被靜默丟掉（Python 3.12 實測：寫入前 `0x800`，寫入後 `0x0`）。檔案照樣產出、
大小正常，只有解析 zip 結構才看得出來。

要改的是 CPython 真正拿來決定旗標的 hook：

```python
class Utf8ZipInfo(zipfile.ZipInfo):
    def _encodeFilenameFlags(self):
        return self.filename.encode("utf-8"), self.flag_bits | 0x800
```

**這個問題是防呆腳本抓到的**，不是我事先想到的——寫完檢查、跑一次，它就叫了。

### 旗標有兩處，要各驗一次

zip 的每個檔案有**兩份** general purpose flag：central directory 一份、
local file header 一份。`zipfile` 的 `flag_bits` 讀的是 central directory，
有些打包工具只設其中一處，而各家解壓工具讀哪一處並不一致。

實測本包 14 個 entry，兩處都是 `0x0800`（bit 11 ON），檔名全 ASCII。

> **[雷] 定位 local header 要用 central directory 記錄的 `header_offset`，
> 不要暴力搜尋 `PK\x03\x04`。** `themes/*.zip` 與 `fonts.dat` 本身就是 zip，
> 存進外層後內部仍保留那個特徵——暴力搜尋會掃到巢狀內容，誤報 37 筆
> 「`Geneva.bin` / `icons/*.png` / `FreeMono.ttf` 沒開旗標」，
> 而那些檔案根本不在我們的包裡。第一次驗證就是這樣誤判的。

`check_windows_zip.py --self-test` 因此有兩輪正對照：一輪餵六條全違反的包，
一輪餵「central directory 有旗標、local file header 沒有」的包（後者要手工改 bytes，
`zipfile` 造不出來）。只驗 `flag_bits` 的檢查會完全放行第二種。

## Windows：mingw runtime 不是系統 DLL

mingw 編出來的 exe 預設動態連結 `libwinpthread-1.dll` / `libgcc_s_seh-1.dll` /
`libstdc++-6.dll`。那些不是 Windows 系統 DLL，玩家機器上沒有，一開就是
「找不到 libwinpthread-1.dll」——而這在 Linux 上完全測不出來。

修法是 configure 時給：

```
LDFLAGS='-static-libgcc -static-libstdc++ -Wl,-Bstatic,--whole-archive -lwinpthread -Wl,--no-whole-archive,-Bdynamic'
```

但**不要相信它成功了**。`build_windows.sh` 收尾用 `objdump -p` 問 exe「你到底要什麼」，
把非系統 DLL 自動補進 `win-deps/`，補不到就 exit。該帶什麼是問出來的，不是記的。

結果：最終只剩 `SDL2.dll` 一個外部依賴。

## configure 選項會隨版本 drift

ScummVM v2.8.0 **沒有** `--disable-mpcdec` / `--openmpt` / `--mikmod` / `--mpeg2` / `--a52`。
傳一個它不認得的，整個 configure 直接 error 退出。

- Windows：`build_windows.sh` 先跑 `./configure --help` 抓出認得的選項再過濾，
  **並把被丟掉的印出來**（靜默過濾等於把「flag 打錯字」變成看不見的問題）。
- macOS：workflow 是靜態 YAML，所以**在 Linux 上先對過一次**再送 CI。
  這一步省掉一輪 mac runner（約 15–20 分鐘加排隊）。換 `SCUMMVM_TAG` 時要重對。

## macOS：四個「CI 綠燈但玩家端壞掉」的地雷

1. **不用 brew 的 sdl2**。2026 起 brew 的 `sdl2` 是 sdl2-compat——把 SDL2 API 架在 SDL3 上的 shim，
   runtime 才 `dlopen libSDL3`。打包工具抓不到 runtime 依賴，玩家端黑畫面，而裝了 SDL3 的
   開發機測不出來。改自 release tarball 編 pinned 真 SDL2，並斷言體積 > 1MB 且 `otool` 查無 SDL3。
2. **universal 用 per-arch + `lipo -create`**，不是單次餵兩個 `-arch`。ScummVM 的 configure 是
   手寫 shell script 不是 autoconf，雙弧會讓它的版本解析炸掉。
3. **x86_64 那一弧整個包進 `arch -x86_64`**。configure 用 `uname` 判 `_host_cpu` 決定要不要開
   ARM NEON，只在 CXXFLAGS 給 `-arch x86_64` 它並不知道，於是把 `blit-neon.cpp` 排進 x86_64 build，
   clang 直接 `#error`。
4. **不用 dylibbundler**。per-arch 路線下兩弧各自連到不同 prefix 的 SDL2，dylibbundler 只會複製
   其中一弧的非-fat dylib → 主程式雙弧但 SDL2 單弧 → 另一半使用者一開就閃退，
   而「有沒有 dylib」的檢查會放行。改成手動 `lipo` + `install_name_tool` + 重新 ad-hoc 簽章，
   並斷言**主 binary 與 Frameworks 內的 SDL2 都是雙弧**。

另：ScummVM 的 configure 只從環境變數讀 `CXXFLAGS`/`LDFLAGS`，不能當 `KEY=VALUE` 位置參數
（同一輪腳本裡 SDL2 是 autoconf 吃得下，很容易誤以為 ScummVM 也吃）。
macOS 沒有 GNU `sha256sum`，只有 `shasum -a 256`。

### 第五個地雷：`ports.mk` 裡的 PowerPC 遺物

`scummvm-static` target 硬寫了 `-force_cpusubtype_ALL`（`ports.mk:555`），
註解自己說是「to ensure the binary runs on every PowerPC machine」。
Xcode 15+ 的新 linker 已經移除這個選項：

```
ld: unknown options: -force_cpusubtype_ALL
```

**整包 .o 都編完了才倒在最後的連結那一步**，特別浪費。workflow 裡用 sed 拿掉，
不動引擎 patch（`ports.mk` 不在 `engines/mads/`，不影響引擎指紋）。

判斷 sed 有沒有生效時**只看非註解行**——那個字串在上一行的註解裡也有，
連註解一起比會永遠誤判成「沒生效」。

### 這條 CI 跑了三輪才綠，每一輪的根因都不一樣

| 輪 | 倒在哪 | 根因 |
|---|---|---|
| 1 | 套 patch | **我的驗證條件寫錯**：grep 的是 `chtEnabled`，但 font.cpp 裡是 `cht->enabled()`。patch 一直是好的 |
| 2 | 連結 arm64 | `ports.mk` 的 `-force_cpusubtype_ALL` |
| 3 | — | 全綠 |

第一輪那個特別值得記：那個檢查**從本機第一次執行就在誤報**，而我當時只看了輸出尾巴和
「cht.cpp 存不存在」，**沒看退出碼**，把 exit 5 當成功，一路帶到 CI 才炸。

教訓有兩層：
1. **驗證條件本身也要驗證**——拿一份「已知是對的」輸入餵進去，確認它說通過；
   再拿一份「已知是錯的」，確認它會叫。
2. **抽查會漏**。單一 grep 只涵蓋一個檔，另外 21 個檔沒套到也看不出來。
   改成比對引擎指紋，`engines/mads/` 底下 124 個 `.cpp`/`.h` 任何一處不對都會擋下。

順帶：`--force_cpusubtype_ALL` 那次，我第一直覺是去改 SDL2 的 `sdl2-config`
（因為錯誤訊息裡有 `sdl2-config --static-libs`）。先去 SDL2 2.30.9 原始碼 grep 了一次，
**零命中**，才回頭找到真正的來源。憑訊息裡最顯眼的字串猜來源，會改錯地方。

## leak-scan

`tools/leak_scan.py` 掃五類版權素材：遊戲資料、MT-32 ROM、手冊掃描、原版音訊/影片、
第三方原始字庫（倚天 `STDFONT.15` 等）。放行 ScummVM 的 GPL 素材與自製的譯文/衍生字型。

**它在第一次 push 前抓到兩件事**：

- AppImage staging 裡的 `rexopen.res` / `rexend1-3.res`。`.gitignore` 當時只寫了大寫 `*.RES`，
  而 **git 的 ignore 比對區分大小寫**，小寫那組整批躲過。
- `workplace/font-src/` 的倚天原始字庫。烘出來只含 2,409 字的 `rex_big5.fnt` 是衍生物，
  跟散布整份商業字庫是兩回事。

## 所有檢查工具都自帶正對照

`check_windows_zip.py --self-test`、`leak_scan.py --self-test` 會造一個「每條都違反」的輸入
餵進同一套規則，確認每條都叫得出來。

做成子指令而不是一次性的手工驗證，是為了讓它不會被忘記。**沒有紅字有兩種可能——
包是好的，或檢查自己壞了**，而這兩件事看起來一模一樣。

## 中文資料有兩份，同步失敗是靜默的

| 路徑 | 角色 |
|---|---|
| `cht-data/` | 版控裡的來源。重烘字型、合併譯文、改譯名都改這裡 |
| `workplace/game/` | 引擎執行時實際讀的（跟遊戲資料放在一起，gitignore） |

打包腳本從 `cht-data/` 取，但**實機驗證跑的是 `workplace/game/`**。兩者沒有自動同步。

2026-08-07 白跑一輪：補了 199 則動畫內嵌訊息、字型重烘成 2,409 字，然後直接跑實機
驗證。截圖「看起來都正常」——因為那些畫面本來就不含新增的內容。真正的徵兆藏在
`-d 1` 的 log 裡：

```
[CHT] 中文化啟用：字型 2394 字 (16x15)，替換表 4357 筆
```

**是舊的數字，而沒有任何東西會因此報錯。**

修法是 `tools/sync_cht_data.sh`：複製 + 比 md5 + 印出「替換表 N 筆、字型 M 字」，
讓它跟引擎啟動時那行直接對照。驗證腳本（`verify_anim_cht.sh`）也加了反查——
引擎讀到的筆數跟 `game/` 對不上就 exit 5，不讓它安靜地驗一份舊表。

通則：**同一份資料存在兩個地方，就要有人負責證明它們一致**，而且那個證明要出現在
每次驗證的輸出裡，不能只寫在文件上。

## 已決定：`workplace/out/` 底下已入庫的產物維持現狀

公開 repo 上有 99 個 `workplace/out/` 檔案是初版 commit 帶上去的：

| 內容 | 數量 |
|---|---|
| `batches-orig/` 遊戲英文原文全量 | 30 檔、4,360 行 |
| `batches/` 原文＋譯文對照 | 30 檔 |
| `text/` 抽字產物 | 5 檔 |
| 驗證截圖（`big5-verify`／`dsr-*`／`gameplay*`／`gp-sync`） | 30 餘張 |

嚴格對照 §5 的「公開 repo 天然 patch-only」，英文原文與遊戲截圖不在那個清單裡。
**使用者 2026-08-07 決定：維持現狀，不移除、不改寫歷史。**

寫下來是為了讓這件事有結論。它已經被翻出來檢討過一次，沒有紀錄的話下一輪盤點
還會再被當成待修問題提一遍 —— 而每提一次都要重新查一次遠端、重新問一次。

不過**新增的產物預設不入庫**：`.gitignore` 已從逐項列舉改成整個 `workplace/out/` ignore。
原本一行一個子目錄的寫法，每新增一種產物就要記得補一行 ——
2026-08-07 一口氣多了 `gp-sync2/`、`gp-sync3/`、`gp-final/`、`intro/`、`intro2/`、
`attract/`、`anim/`、`animverify/` 八個目錄，**全部漏掉**。
真的要讓某個檔進版控，用 `!` 開明確例外，讓它在 diff 裡顯眼。

## 「檢查工具不在」跟「檢查通過」長得幾乎一樣

`apply_patches.sh` 收尾會比對引擎指紋，但原本寫的是：

```bash
if command -v python3 >/dev/null; then
    python3 engine_fingerprint.py "$DEST" --expect "$EXPECT" || exit 6
else
    echo "（無 python3，略過指紋比對）"      # ← 然後就過去了
fi
```

`rex-mingw` image 沒裝 python3。於是 **Windows 包的引擎指紋從頭到尾沒有被比對過一次**，
而輸出長這樣：

```
=== 套用繁中化 patch ===
（無 python3，略過指紋比對）
=== patch 套用完成：/w/build/mingw-tree ===
```

看起來完全正常。剩下的只有一個 `grep -q 'ChtSupport' font.cpp` 的抽查 —— 那只證明
22 個檔裡有 1 個套上了。

現在改成 `###` 開頭（跟真正的錯誤同格式）並 `exit 7`，訊息裡直接寫正確做法。
正對照跑過：在 `rex-mingw` 裡執行確實 exit 7。

**Windows 的正確流程**（順序不能顛倒）：

```bash
# 1. 用 rex-cht:dev 套 patch —— 它有 python3，指紋才驗得到
docker run --rm -v "$PWD:/w" -w /w rex-cht:dev bash tools/apply_patches.sh /w/build/mingw-tree
# 2. 在**宿主機**跑建置（這支腳本自己會開 rex-mingw 容器，不要再包一層 docker run）
bash tools/build_windows.sh
```

> 順帶一個踩過的：把 `build_windows.sh` 整支包進 `docker run rex-mingw` 裡跑，
> 會因為容器內沒有 docker 而靜靜停在第一個 `docker run` —— **退出碼是 0**，
> 只是什麼都沒編出來。要驗的是產物存不存在，不是退出碼。

## leak-scan 一直沒掃過 macOS 那包

`leak_scan.py` 原本只認 zip 與目錄。macOS 交付是 `.tar.gz` 與 `.dmg`，
餵進去會得到：

```
### 不認得的目標：dist-all/RexNebular-CHT-macos-universal.tar.gz（要 zip 或目錄）###
```

這行混在一堆 ✓ 中間，讀起來像「我指令打錯了」而不是「這一包沒被檢查」。
於是三平台裡就 macOS 從來沒過過 leak-scan。

已補上 tarfile 支援，`.dmg` 仍要先解開（訊息裡有寫）。三平台現在一次掃完：

```bash
python3 tools/leak_scan.py \
    dist-all/rexnebular-cht-patch.zip \
    dist-all/rexnebular-cht-win64.zip \
    dist-all/RexNebular-CHT-macos-universal.tar.gz
```

通則跟 `apply_patches.sh` 那條同源：**「工具不支援這個輸入」跟「這個輸入沒問題」
在輸出上要長得不一樣**，而且前者要能讓人一眼看出覆蓋範圍少了一塊。

## 已知限制：主選單中文在 wine 下未生效（Linux 正常）

主選單的 baked-art 中文標籤，**Linux 下三種情境都正常**：

| 情境 | 結果 |
|---|---|
| 資料放在 `game/` 目錄，靜止截圖 | 中文（選單區黃色像素 2077） |
| 同上，截圖前大量移動滑鼠製造 dirty | 中文（2077） |
| **用 Windows 包的目錄結構**（`--extrapath=cht-data --path=game`） | 中文（2077） |

但同一份 patch 交叉編成 `scummvm.exe`、用 **wine** 跑，主選單是英文（8268）。

已排除的原因：

- **不是資料**：包內 `rex_cht.tsv` 4562 筆、`menu:` 六筆都在，md5 與來源一致。
- **不是建置**：包內 `ENGINE.txt` 指紋與來源一致，`grep -a "menu:%d" scummvm.exe` 命中。
- **不是程式碼沒跑**：wine 下開 `--debuglevel=2`，`[CHT] 選單項 N 取色 index=236`
  五行全部印出來 —— `drawChtLabels()` 有執行，中文有畫進文字層。
- **不是參數或路徑**：Linux binary 用完全相同的 `--extrapath=cht-data --path=game`
  結構跑，結果是中文。

也就是說：**同一段程式碼、同一份資料，在 wine 下走到了不同的結果**，
而目前的證據指向繪製／合成時序，還沒定位到確切原因。

**影響範圍**：只有主選單那六個標籤。遊戲內的對白、指令表、物品名、
片尾在 wine 下都正常（`win-ingame.png` 可證）。

**尚未驗證的**：真正的 Windows 上是否也如此。手上沒有 Windows 機器，
wine 的繪製路徑與真機不同，不能拿 wine 的結果推論真機。

> 診斷這件事時最有用的一步是**鑑別診斷**：把「Windows 包的目錄結構」搬到 Linux 上跑。
> 那一次就把「參數／路徑」整類原因排除掉了，剩下的才是 wine 本身。
> 判準也要能分辨結果 —— 英文選單 8268 像素、中文 2077，差距夠大才敢用它自動判。
