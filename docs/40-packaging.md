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
- `workplace/font-src/` 的倚天原始字庫。烘出來只含 2,394 字的 `rex_big5.fnt` 是衍生物，
  跟散布整份商業字庫是兩回事。

## 所有檢查工具都自帶正對照

`check_windows_zip.py --self-test`、`leak_scan.py --self-test` 會造一個「每條都違反」的輸入
餵進同一套規則，確認每條都叫得出來。

做成子指令而不是一次性的手工驗證，是為了讓它不會被忘記。**沒有紅字有兩種可能——
包是好的，或檢查自己壞了**，而這兩件事看起來一模一樣。
