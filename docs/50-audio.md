# 聲音：Sound Blaster 的兩層，與 MT-32 為什麼做不到

## Sound Blaster 是兩層，別只看一層

1992 年講「支援 Sound Blaster」，指的是兩件不同的事，這款兩層都有，
ScummVM 的 MADS 引擎也兩層都實作了：

| 層 | 硬體 | 遊戲資料 | ScummVM 實作 |
|---|---|---|---|
| **音樂** | SB 卡上的 **YM3812**——跟 AdLib 卡是同一顆 FM 合成晶片 | `asound.001–009` | `engines/mads/sound.cpp:45` `_opl = OPL::Config::create()` |
| **音效** | SB 的 **DAC**（數位取樣播放） | `REX009.DSR`（22 筆）、`ACT002.DSR`（13 筆） | `engines/mads/audio.cpp:92` `playSound()` |

所以「AdLib 音樂」和「Sound Blaster 音樂」在這款是同一件事——SB 的 FM 部分就是 AdLib 相容。
差別在 SB 多了數位音效那一層。

`asound` / `isound` / `psound` / `rsound` 這四組**不是音樂資料，是 DOS 驅動程式**：
檔頭 `4d 5a`（MZ），內含 `AGAAdlibOvl1 09-13-92`、`RLND AGAdemo 9-13-92` 之類的字串。
ScummVM 是把 asound 那支驅動的行為**重新實作**成 C++（`nebular/sound_nebular.cpp` 的 `ASound`），
不是去執行原始驅動。

### 播放設定

包裡的 `scummvm.ini` 明確寫死，不靠預設值：

```ini
music_driver=adlib
music_volume=192
sfx_volume=255
speech_volume=255
```

> `sfx_volume` 不設的話音效會停在 ScummVM 的預設值，錄音或實玩時會覺得「只有音樂」。

## DSR 格式

從 `engines/mads/audio.cpp:68-88` 讀出來的，不是猜的：

```
uint16  entryCount
每筆：  uint16 frequency      取樣率
        uint32 channels
        uint32 compSize       FAB 壓縮後大小
        uint32 uncompSize     解開後大小
        uint32 offset         檔案內位移
資料本身 FAB 壓縮，解開後是 unsigned 8-bit PCM
（audio.cpp:120 makeRawStream(..., Audio::FLAG_UNSIGNED)，沒有 FLAG_16BITS）
```

`tools/extract_dsr.py` 照這個格式解，**22 筆全部解出、0 失敗**，8000 Hz，
最長 4.98 秒。解開後的大小與 header 宣告完全相符——這是 FAB 解壓正確的證明。

> `REX009.DSR` **不在遊戲根目錄**，封在 HAG 裡。`ls` 看不到，得掃 HAG（1493 筆資源之一）。
> 掃描時先做正對照：拿 `QUOTES.DAT` / `VOCAB.DAT` 這種一定存在的資源確認掃描本身有效。
> 第一次掃回 0 筆，就是靠正對照當場發現是掃描寫錯，不是檔案不存在。

## [HARD] MT-32 做不到

**別再試了**，三條路全堵，每條都有一手證據：

**① ScummVM 的 MADS 引擎沒有 MIDI 路徑。**
`SoundManager` 建構子直接建 OPL（`sound.cpp:45`），那是唯一的音樂裝置。
全引擎 grep `MidiDriver` / `MidiParser` / `detectDevice` / `MT_MT32` **零命中**。
`_preferRoland` 在 `sound.cpp:43` 寫死 `false`，而且只有 `phantom/` 會讀它（拿去選音效編號），
`nebular` 完全不碰。**`-e mt32` 對這款是靜默無效的**——不報錯、不提示，就是照放 AdLib。

**② 沒有原版執行檔。** 遊戲 zip 裡 56 個檔全是資料，沒有任何 `.EXE`，
DOSBox + Munt 跑原版這條也不通。

**③ `rsound.*` 不是音樂資料。** 那是九支 16-bit DOS 驅動程式（MZ 檔頭）。
要 MT-32 等於逆向它們、把 MIDI 輸出邏輯重寫成 C++ 餵給 Munt——
那是幫 ScummVM 補完 MADS 的 MT-32 支援，獨立專案的規模。

因此三平台一律 `--disable-mt32emu`（Munt 對這款完全無用，編進去只是把 binary 撐肥），
並反向反查 `config.mk` 沒有 `USE_MT32EMU = 1`。

### 怎麼發現的：頻譜比對

我一開始**真的錄了 416 秒「MT-32」音訊**，log 沒有任何錯誤，音量正常。
如果就這樣交出去，會是一份掛著 MT-32 名字的 AdLib 錄音。

抓到它的方法是**頻譜比對**：錄一份 AdLib、錄一份宣稱 MT-32 的，
各取 30 秒用 `showspectrumpic` 產圖。兩張的諧波梳狀結構與脈衝間隔**完全同型**——
根本沒切換過。

> 通則：驗證「某個設定有沒有生效」，不要看「我設了參數」也不要只看「log 沒報錯」。
> 找一個**會因為該設定而改變的可觀測量**，跟對照組比。

## 音樂進點：前 30 秒是靜音

實測值，不是套 SCUMM 的結論：

| 時間 | mean | 說明 |
|---|---|---|
| 0–30s | −91 dB | 完全靜音（主選單與載入期） |
| 30s 之後 | −27 ~ −31 dB | 音樂穩定播放 |

錄音要送鍵推進（主選單 → 開始新遊戲 → 難度選擇），素材取 30 秒之後。
`tools/record_audio_sb.sh` 會逐 15 秒掃描印出音量表，換素材時重看一次。

## 推廣片的音訊

兩層都用原版真實素材，沒有一個位元是合成的：

- **配樂**：`tools/record_audio_sb.sh` 用 SDL disk audio 實錄的 AdLib FM 輸出
- **音效**：`tools/extract_dsr.py` 從 `REX009.DSR` 抽出的原版 PCM，放在版面切換點

> `amix` 之前要先 `aformat=sample_rates=44100:channel_layouts=stereo` 對齊——
> 音效是 8000 Hz 單聲道，直接混會變調。`normalize=0` 則是避免 amix 因為輸入數量
> 把整體音量除下去。

**IP**：原版配樂與音效都是 MicroProse 的著作權。影片只留在 `dist-all/`（gitignore），
不隨 repo 散布。要公開上傳前另外評估。
