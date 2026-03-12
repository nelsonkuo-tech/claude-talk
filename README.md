# Claude Talk

Press-to-talk voice input for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Hold a key, speak, and your words are transcribed and pasted into the terminal.

Uses [faster-whisper](https://github.com/SYSTRAN/faster-whisper) for fast, local, offline speech recognition. No API keys needed.

> **macOS only** — relies on macOS Accessibility APIs, AppleScript, and system audio.

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
