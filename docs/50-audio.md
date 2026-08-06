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

## 推廣片的音訊：錄真實遊玩，不後製混音

最終版（`tools/make_promo2.sh`）用 `tools/record_gameplay_sync.sh` 錄真實遊玩，
畫面與聲音**由同一個 ffmpeg 行程錄**，時間軸天生對齊。遊玩片段裁切時
畫面與音訊從同一時間點一起裁，音效就落在它該響的那一刻。

### [HARD] 不能用 SDL 的 disk audio driver 錄影片配樂

它是「盡快把 mixer 輸出寫檔」，**不受真實時間約束**——實測 110 秒的遊玩錄出
**397 秒**音訊，音畫差 3.6 倍。`SDL_DISKAUDIODELAY` 只能減緩，不能讓它變成即時。

正解是 **PulseAudio null sink**（`docker/Dockerfile.record`）：沒有實體硬體，
但**按真實時間消耗取樣**（模擬音效卡時鐘），所以 ScummVM 以正常速度產生音訊。

```bash
pulseaudio --start --exit-idle-time=-1 -n \
    --load="module-null-sink sink_name=rex" --load="module-native-protocol-unix"
# ScummVM 端：SDL_AUDIODRIVER=pulse PULSE_SINK=rex
# ffmpeg 端： -f x11grab -i :99  -f pulse -i rex.monitor
```

disk audio driver 仍適合**只要音訊素材**的場合（`record_audio_sb.sh`），
那裡不在乎它跑多快。

### [雷] 「音畫等長」這個檢查，我寫錯過兩次

1. 用 `stream=duration` 取長度。邊錄邊被 kill 的 mkv，stream 層沒有 duration，
   ffprobe 回 `N/A`——而 awk 拿兩個 `N/A` 相減得 0，印出「✓ 差 0s，同步」。
   **檢查在拿不到資料時靜默通過，比沒有檢查更糟。**
2. 改用「容器 duration vs 音訊長度」。容器 duration 取的是**最長那一軌**，
   所以 110s 影片配 397s 音訊的檔，容器就是 397s，兩者永遠一致。

正解是比 **video 軌 vs audio 軌**，兩邊都解碼實測：

```bash
track_len() {   # $1 檔案  $2 v|a
    ffmpeg -v info -i "$1" -map "0:$2" -f null - 2>&1 \
      | grep -oE 'time=[0-9][0-9:.]+' | tail -1 | cut -d= -f2 \
      | awk -F: '{print ($1*3600)+($2*60)+$3}'
}
```

正對照（拿已知沒同步的那份餵進去）：

| 素材 | 影片 | 音訊 | 差 | 判定 |
|---|---|---|---|---|
| PulseAudio 版 | 138.9s | 140.0s | 1.1s | ✓ 同步 |
| SDL disk audio 版 | 110.0s | 397.2s | 287.2s | ✗ 沒同步 |

**這個判準前兩版都是拿真檔測「通過」就收工，正對照一做就露餡。**

### 另一條路：直接抽 DSR 音效後製混入

`tools/extract_dsr.py` 抽出的音效也可以後製混進靜態卡片版（v1 就是這樣做的）。
位置是人為指定的，不是遊戲觸發的，但對純卡片式的片子夠用。

> `amix` 之前要先 `aformat=sample_rates=44100:channel_layouts=stereo` 對齊——
> 音效是 8000 Hz 單聲道，直接混會變調。`normalize=0` 則是避免 amix 因為輸入數量
> 把整體音量除下去。

**IP**：原版配樂與音效都是 MicroProse 的著作權。影片只留在 `dist-all/`（gitignore），
不隨 repo 散布。要公開上傳前另外評估。
