# Claude Talk

Press-to-talk voice input for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Hold a key, speak, release — your voice is transcribed locally and pasted directly into the terminal. Everything runs on-device with no API keys, no cloud calls, and no data leaving your machine.

> **macOS 26+ only** (Apple Silicon)

## Download

**[Download Claude Talk v1.1.0 (.dmg)](https://github.com/nelsonkuo-tech/claude-talk/releases/download/v1.1.0/ClaudeTalk-1.1.0.dmg)**

Open the DMG, drag ClaudeTalk to Applications, done.

---

**Claude Talk** — 為 Claude Code 打造的按鍵語音輸入工具。

按住快捷鍵說話、放開即完成轉錄，文字自動貼入終端機。所有語音辨識都在本機完成，不需要 API key，不上傳任何資料。

> **僅支援 macOS 26+**（Apple Silicon）

## 下載

**[下載 Claude Talk v1.1.0 (.dmg)](https://github.com/nelsonkuo-tech/claude-talk/releases/download/v1.1.0/ClaudeTalk-1.1.0.dmg)**

打開 DMG，將 ClaudeTalk 拖入 Applications 資料夾即可。

---

## Features

- **Native macOS app** — menu bar icon, no terminal window needed
- **macOS 26 Liquid Glass UI** — pill-shaped overlay with real-time FFT waveform
- **Two recording modes** — hold-to-record or tap-to-toggle
- **Glass style options** — Auto (follow background), Light Glass, Dark Glass
- **Local speech-to-text** via [faster-whisper](https://github.com/SYSTRAN/faster-whisper), supports 90+ languages
- **~0.5s transcription latency** on Apple Silicon
- **Terminal-aware** — only pastes when a supported terminal is focused
- **Customizable** — hotkey, model size, language, terminal whitelist

## Usage

1. Launch ClaudeTalk — mic icon appears in menu bar
2. Grant **Accessibility** and **Microphone** permissions when prompted
3. Focus on a terminal (Ghostty, iTerm2, Terminal, Warp, Kitty, etc.)
4. **Hold fn key**, speak, **release** — text is transcribed and pasted

### Menu Bar Settings

- **Hotkey** — fn, Option, F5-F12
- **Model** — tiny, base, small, medium
- **Language** — Auto, English, 中文, 日本語, 한국어, Español
- **Recording mode** — Hold to Record / Tap to Start-Stop
- **Appearance** — Auto, Light Glass, Dark Glass
- **Terminals** — whitelist of supported terminal apps

## CLI Version

The original CLI version is still available:

```bash
brew install portaudio ffmpeg
pip install claude-talk
claude-talk
```

## Model Sizes

| Model    | Size    | Speed   | Accuracy |
|----------|---------|---------|----------|
| `tiny`   | ~75 MB  | Fastest | Basic    |
| `base`   | ~150 MB | Fast    | Good     |
| `small`  | ~500 MB | Medium  | Better   |
| `medium` | ~1.5 GB | Slow    | Best     |

The app ships with `base`. Switch models from the menu bar.

## Build from Source

```bash
git clone https://github.com/nelsonkuo-tech/claude-talk.git
cd claude-talk/ClaudeTalk
xcodegen generate
bash build-release.sh
```

Requires: Xcode 17+, Python 3, faster-whisper, PyInstaller.

## License

MIT
