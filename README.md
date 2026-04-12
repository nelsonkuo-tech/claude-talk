# Claude Talk

Voice input for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and any app on your Mac.

Speak naturally — your voice is transcribed locally, polished by AI, and pasted into the focused app. Works in terminals, Notes, chat apps, and more. Transcription runs on-device; optional AI polish uses your own API key.

> **macOS 26+ only** (Apple Silicon)

## Download

**[Download Claude Talk v1.3.1 (.dmg)](https://github.com/nelsonkuo-tech/claude-talk/releases/tag/v1.3.1)**

Open the DMG, drag ClaudeTalk to Applications, done.

---

**Claude Talk** — Mac 上的語音輸入工具，為 Claude Code 及所有 App 打造。

對著麥克風說話，語音在本機轉錄後由 AI 潤飾，自動貼入當前 App。支援終端機、備忘錄、聊天軟體等。語音辨識完全在裝置上執行；AI 潤飾使用你自己的 API key。

> **僅支援 macOS 26+**（Apple Silicon）

## 下載

**[下載 Claude Talk v1.3.1 (.dmg)](https://github.com/nelsonkuo-tech/claude-talk/releases/tag/v1.3.1)**

打開 DMG，將 ClaudeTalk 拖入 Applications 資料夾即可。

---

## Features

- **Native macOS app** — menu bar icon, no terminal window needed
- **macOS 26 Liquid Glass UI** — pill-shaped overlay with real-time FFT waveform
- **Works in any app** — terminals, Notes, Keynote, chat apps, and more
- **AI polish (always-on)** — cleans up filler words and grammar via LLM
- **Translation mode** — speak in any language, output in your target language
- **Two recording modes** — hold-to-record or tap-to-toggle
- **Glass style options** — Auto (follow background), Light Glass, Dark Glass
- **Local speech-to-text** via [faster-whisper](https://github.com/SYSTRAN/faster-whisper), supports 90+ languages
- **~0.5s transcription latency** on Apple Silicon
- **Multi-display aware** — overlay follows your active screen
- **Customizable** — hotkey, model size, language, app whitelist

## Usage

1. Launch ClaudeTalk — mic icon appears in menu bar
2. Grant **Accessibility** and **Microphone** permissions when prompted
3. Focus on any supported app (terminals, Notes, chat apps, etc.)
4. **Press hotkey**, speak, **press again** — text is transcribed, polished, and pasted

### Menu Bar Settings

- **Hotkey** — fn, Option, F5-F12
- **AI Mode** — Polish (clean up speech) or Translate (to target language)
- **Model** — tiny, base, small, medium
- **Language** — Auto, English, 中文, 日本語, 한국어, Español
- **Recording mode** — Hold to Record / Tap to Start-Stop
- **Appearance** — Auto, Light Glass, Dark Glass
- **Apps** — whitelist of supported apps (terminals + any app you add)

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
