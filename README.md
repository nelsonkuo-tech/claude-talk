# Claude Talk

Press-to-talk voice input for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Hold a key, speak, release — your voice is transcribed locally and pasted directly into the terminal. Powered by [faster-whisper](https://github.com/SYSTRAN/faster-whisper), everything runs on-device with no API keys, no cloud calls, and no data leaving your machine.

**Features:**
- Hold-to-record hotkey (default: Option/Alt, customizable)
- Local speech-to-text via Whisper (supports 90+ languages)
- Auto-detects language or can be pinned to one
- Only pastes when a terminal is focused — won't leak into other apps
- Sound feedback on record start/stop
- Lightweight, single-command install

> **macOS only** — relies on macOS Accessibility APIs, AppleScript, and system audio.

---

**Claude Talk** — 為 Claude Code 打造的按鍵語音輸入工具。

按住快捷鍵說話、放開即完成轉錄，文字自動貼入終端機。基於 [faster-whisper](https://github.com/SYSTRAN/faster-whisper)，所有語音辨識都在本機完成，不需要 API key，不上傳任何資料。

**功能特色：**
- 按住說話、放開送出（預設 Option/Alt，可自訂）
- 本機 Whisper 語音轉文字，支援 90+ 種語言
- 自動偵測語言，也可指定單一語言
- 僅在終端機獲得焦點時才貼上，不會誤輸入到其他應用
- 錄音開始 / 結束音效回饋
- 輕量、一行指令安裝

> **僅支援 macOS** — 依賴 macOS Accessibility API、AppleScript 及系統音訊。

## Install

### 1. System dependencies

```bash
brew install portaudio ffmpeg
```

### 2. Install claude-talk

```bash
pip install claude-talk
```

Or install from source:

```bash
git clone https://github.com/nelsonkuo-tech/claude-talk.git
cd claude-talk
pip install .
```

### 3. Download the Whisper model (optional)

The model downloads automatically on first run (~150 MB for `base`). To pre-download:

```bash
claude-talk --download
```

### 4. Grant macOS permissions

- **Microphone**: auto-prompted on first run
- **Accessibility**: System Settings > Privacy & Security > Accessibility > add your terminal app (Terminal, iTerm2, Ghostty, etc.)

## Usage

```bash
claude-talk                            # Hold Option/Alt to speak
claude-talk --key f5                   # Use F5 instead
claude-talk --language zh              # Force Chinese
claude-talk --language en              # Force English
claude-talk --model small              # Use a larger model for better accuracy
claude-talk --no-sound                 # Disable sound feedback
claude-talk --terminals ghostty,kitty  # Custom terminal whitelist
```

### How it works

1. Hold the hotkey (default: Option/Alt)
2. Speak
3. Release the key
4. Text is transcribed locally and pasted into your terminal

The tool only pastes when a supported terminal is focused, so it won't accidentally type into other apps.

### Model sizes

| Model    | Size   | Speed   | Accuracy |
|----------|--------|---------|----------|
| `tiny`   | ~75 MB | Fastest | Basic    |
| `base`   | ~150 MB| Fast    | Good     |
| `small`  | ~500 MB| Medium  | Better   |
| `medium` | ~1.5 GB| Slow    | Best     |

Default is `base` — a good balance for most use cases. Use `small` or `medium` if you need better accuracy for technical terms or non-English languages.

## License

MIT
