# Claude Talk — Swift Rewrite with Notch UI

## Goals

1. **Simple to use** — Download `.app`, open, done. Zero dependencies.
2. **Clean, beautiful UI** — Notch integration, minimal, unobtrusive.
3. **Free, efficient** — Local inference (no API keys, no cloud calls), open source (MIT). Initial model download requires internet; after that, fully offline.

## Overview

Rewrite Claude Talk from Python + faster-whisper to a native macOS Swift app using whisper.cpp. Add a Notch UI that blends with the MacBook notch area, and a minimal Menu Bar presence. The app should feel like a native macOS tool — lightweight, invisible until needed.

## Architecture

Single-process Swift macOS app:

```
Claude Talk.app (Swift)
├── AudioEngine        — AVFoundation microphone recording
├── TranscriptionEngine — whisper.cpp (local inference, no network)
├── PostProcessor      — Rule-based filler word removal
├── InputSimulator     — CGEvent keyboard simulation (paste into terminal)
├── NotchOverlay       — NSPanel + Core Animation (notch UI)
└── MenuBarController  — NSStatusItem (status icon + dropdown settings)
```

No IPC, no helper processes, no Python runtime.

### Dependencies (Swift packages / C libraries)

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — Speech-to-text inference, vendored C source with Swift bridging header
- AVFoundation — Audio recording (system framework)
- CoreGraphics — CGEvent for keyboard simulation and global hotkey capture (system framework)
- AppKit — NSPanel, NSStatusItem, NSWindow (system framework)

No third-party UI frameworks. All system frameworks + whisper.cpp only.

### whisper.cpp Integration

Vendor whisper.cpp C source into the Xcode project with a bridging header. Do not use SPM — vendoring gives full control over build flags and Metal/Accelerate optimizations. Compile whisper.cpp with `-O3` and Metal support (Apple Silicon) or Accelerate (Intel).

### Global Hotkey Capture

Use `CGEvent.tapCreate` to monitor key events globally. This requires the Accessibility permission already requested during onboarding.

- Default hotkey: **Fn** key (avoids conflict with Option's accent character input)
- Alternative options available via Menu Bar submenu: Fn, Right Option, Left Option, F5-F12
- Hotkey change UX: submenu with predefined key options (no free-form capture)

### Accessibility Permission Handling

- On launch, check Accessibility via `AXIsProcessTrusted()`
- If not granted: show a persistent Menu Bar badge (red dot) and a "Grant Accessibility" menu item that opens System Settings > Privacy > Accessibility
- Hotkey capture and paste simulation are disabled until permission is granted

## User Experience

### First Launch

1. App opens → shows a single onboarding window:
   - Auto-downloads Whisper `base` model (~150 MB) with progress bar
   - Requests Microphone permission (system dialog)
   - Requests Accessibility permission (with instructions)
   - Choose hotkey (default: Option/Alt, dropdown to change)
2. "Ready" → window closes, app lives in Menu Bar

### Daily Use

```
User opens app (or it auto-starts on login)
  → Menu bar icon appears (small microphone)
  → Hold hotkey in any terminal
  → Notch UI slides out (recording)
  → Release hotkey
  → Notch UI slides back (done)
  → Transcribed text pasted into terminal
```

One action: **hold and speak**.

## Notch UI Specification

### Visual Design

- **Background**: Pure black `#000000`, seamless with MacBook notch
- **Shape**: Pill/rounded rectangle extending below the notch, bottom corners rounded (~20pt radius)
- **Width**: ~1.5-2x the notch width
- **Content layout**: Camera/notch area in center is avoided
  - Left side: Audio waveform animation (5-7 white vertical bars, height follows mic input RMS)
  - Right side: Recording timer in white monospace font (`0:00` format)

### States

| State | Notch UI Behavior |
|-------|-------------------|
| Idle | Nothing visible |
| Recording | Black pill slides down from notch (0.3s ease-in-out). Left: waveform bars animate with audio level. Right: timer counts up. |
| Transcribing | Waveform bars replaced by pulsing dots animation. Timer freezes. |
| Complete (success) | System sound "Pop". Pill slides up into notch (0.3s ease-in-out). |
| Complete (error) | System sound "Basso". Pill slides up into notch. |
| Discarded (too short/silent) | Pill slides up immediately, no sound. Quick visual dismiss so user knows it was intentional. |

### Window Properties (NSPanel)

```swift
// Key properties:
level: .statusBar
styleMask: [.borderless, .nonactivatingPanel]
ignoresMouseEvents: true  // click-through, never steals focus
collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]
isOpaque: false
backgroundColor: .black
hasShadow: false
```

### Positioning

- **MacBook with notch**: Centered horizontally at screen top, Y positioned so top edge aligns with notch bottom edge
- **Mac without notch / external display**: Centered horizontally at screen top, small gap from top. Same pill design, acts as a floating status bar.

### Notch Detection

Detect notch by checking `NSScreen.main?.safeAreaInsets.top > 0` (macOS 12+). If the top safe area inset is greater than zero, a notch is present. If no notch (external display, older Mac), fall back to top-center floating bar.

## Menu Bar

NSStatusItem with a microphone icon. Click to show dropdown:

```
Claude Talk                Running
────────────────────────────────
Hotkey           Option    [▸ change]
Model            base      [▸ tiny/base/small/medium]
Language         Auto      [▸ pin to specific language]
Terminals        Auto      [▸ customize]
────────────────────────────────
☐ Launch at Login
☐ Remove Filler Words
────────────────────────────────
About Claude Talk
Quit
```

No settings window. Everything in the dropdown menu.

### Appearance Customization

Menu Bar 下拉中增加「Appearance」子菜单，让用户自定义 Notch UI 的视觉风格：

```
Appearance                          ▸
  ├── Accent Color                  ▸  White (default) / Purple / Cyan / Green / Orange / Pink
  ├── Waveform Style                ▸  Bars (default) / Dots / Line / 🐱 Cat / 🐰 Rabbit / 🐶 Dog
  └── Pill Style                    ▸  Solid Black (default) / Frosted Glass
```

**Accent Color** — 控制波形动画和计时器文字的颜色：
- White `#FFFFFF`（默认，干净简洁）
- Purple `#A855F7`
- Cyan `#06B6D4`
- Green `#22C55E`
- Orange `#F97316`
- Pink `#EC4899`

**Waveform Style** — 波形动画的形态：
- Bars（默认）— 5-7 根竖条，高度随音量跳动
- Dots — 圆点阵列，大小随音量变化
- Line — 连续波形线，类似音频编辑器
- Cat — 猫咪头像，嘴巴张合幅度跟随音量
- Rabbit — 兔子头像，嘴巴张合 + 耳朵微动
- Dog — 狗狗头像，嘴巴张合 + 舌头弹出

角色动画规格：
- 尺寸：约 28x28pt，放在药丸左侧（取代波形位置）
- 使用 Core Animation 的逐帧动画，3-4 帧循环：闭嘴 → 微张 → 大张 → 微张
- 嘴巴张合幅度映射到麦克风 RMS（安静=闭嘴，大声=大张）
- **8-bit 像素风格**：精致像素画，有阴影和色彩层次（参考图风格），非粗糙简笔
- 每个角色原图 32x32 像素，渲染到 28x28pt，保持像素锐利不模糊
- 角色只显示头部/脸部（notch 药丸空间有限）
- 颜色：每个角色固定配色（不跟 Accent Color 变色，保持角色原始风格）
- Accent Color 仅影响计时器文字和波形模式下的波形颜色
- 渲染时关闭抗锯齿（`NSImage` 的 `interpolation = .none`）
- 转录中状态：闭嘴 + 头上冒出像素 `...` 气泡
- 每个角色 4 帧 sprite sheet：闭嘴 / 微张 / 大张 / 思考
- 三个角色 × 4 帧 = 12 张 PNG，透明背景
- 资源由设计师或 AI 工具生成，打包在 Assets.xcassets 中
- 授权要求：素材必须 MIT/CC0 可商用

**Pill Style** — 药丸背景风格：
- Solid Black（默认）— 纯黑 `#000000`，与 notch 完全融合
- Frosted Glass — 半透明毛玻璃效果（`NSVisualEffectView`, `.dark` material）

所有外观设置存储在 UserDefaults，即时生效，不需要重启。

### Settings Persistence

Store settings in `UserDefaults`. Keys:
- `hotkey` (String, default: "option")
- `modelSize` (String, default: "base")
- `language` (String?, default: nil = auto)
- `terminalWhitelist` ([String], default: auto-detect)
- `launchAtLogin` (Bool, default: false)
- `removeFillerWords` (Bool, default: true)
- `accentColor` (String, default: "white")
- `waveformStyle` (String, default: "bars")
- `pillStyle` (String, default: "solid")
- `promptHint` (String, default: "以下是中英文夹杂的内容。Contains both Chinese and English.")

## Post-Processing: Filler Word Removal

When enabled, apply rule-based removal after transcription, before pasting:

### Chinese filler words
`嗯`, `啊`, `那個`, `就是`, `然後`, `對`, `齁`, `呃`

### English filler words
`um`, `uh`, `uh huh`, `like`, `you know`, `I mean`, `basically`, `actually`, `so yeah`, `right`

Implementation: Simple regex/string replacement. Match whole words only (English) or standalone characters (Chinese). Do not use AI for this — rules are sufficient and keep it fast.

### Custom Dictionary (Misrecognition Fix)

After filler word removal, apply a user-editable dictionary to fix common misrecognitions, especially for code-switching (中英夹杂) scenarios:

Built-in defaults:
```
克劳德 → Claude
吉特 → Git
皮埃 → PR
艾皮艾 → API
蒂普洛伊 → deploy
可米特 → commit
普什 → push
普爾 → pull
```

- Stored as JSON in `~/Library/Application Support/Claude Talk/dictionary.json`
- Users can edit this file to add their own terms
- Menu Bar shows "Edit Dictionary..." item that opens the file in default editor
- Applied as simple string replacement after filler word removal

## Whisper Prompt Hint (Code-Switching Optimization)

whisper.cpp supports `initial_prompt` to hint the model about expected content. This significantly improves code-switching accuracy.

Default prompt:
```
以下是中英文夹杂的内容。Contains both Chinese and English technical terms like Claude Code, git, commit, API, deploy, PR, terminal.
```

- Stored in Settings as `promptHint` (String)
- Menu Bar shows current prompt hint, editable via "Edit Prompt Hint..." (opens small text input dialog)
- Users can customize with their own frequently-used technical terms
- Set to empty string to disable

## Audio Pipeline

```
Hotkey pressed:
  1. Check focused app is a terminal (if not, ignore hotkey entirely)
  2. Start recording (AVFoundation, 16kHz mono float32, memory buffer)
  3. Show Notch UI (recording state)

Hotkey released:
  4. Stop recording
  5. Check duration >= 0.3s, else discard (Notch UI → discarded state)
  6. Check RMS > threshold, else discard (Notch UI → discarded state)
  7. Notch UI → transcribing state
  8. Feed buffer to whisper.cpp (beam_size=5, reduce to 3 on Intel)
  9. Get text → apply filler word removal (if enabled)
  10. Re-check focused app is a terminal (user may have switched)
  11. Simulate Cmd+V paste (CGEvent), preserving clipboard
  12. Notch UI → complete state → slide up
```

Terminal focus is checked **before** recording starts, so the hotkey is invisible in non-terminal apps.

### Terminal Detection

Auto-detect focused app name via NSWorkspace. Built-in whitelist:
- Terminal, iTerm2, Ghostty, Kitty, Warp, Alacritty, WezTerm, Hyper

User can add custom terminal names via Menu Bar dropdown.

### Clipboard Preservation

1. Read current pasteboard contents
2. Set pasteboard to transcribed text
3. Simulate Cmd+V via CGEvent
4. Wait 150ms
5. Restore original pasteboard contents

## Model Management

- Models stored in `~/Library/Application Support/Claude Talk/models/`
- Default: `base` (~150 MB, auto-downloaded on first launch)
- Switching model in Menu Bar triggers download if not cached (show progress in Menu Bar)
- Models: tiny (~75 MB), base (~150 MB), small (~500 MB), medium (~1.5 GB)

## Distribution

### Primary: GitHub Releases
- Universal binary (arm64 + x86_64) `.app` in a `.dmg`
- Users: download → open DMG → drag to Applications
- GitHub Actions CI to build and publish releases

### Future: Homebrew Cask
- `brew install --cask claude-talk`
- Separate task, not in scope for v1

### Signing
- No Apple Developer account needed
- Unsigned app: users right-click → Open on first launch to bypass Gatekeeper
- Acceptable for developer-audience open-source tool

## Legacy Python Version

- Current Python code stays in `legacy/` branch
- `pip install claude-talk` continues to work (pointing to legacy version)
- README updated to point to the new Swift app as primary

## System Requirements

- macOS 14.0+ (Sonoma or later)
- Apple Silicon or Intel Mac
- Microphone
- Accessibility permission

## Out of Scope (explicitly not doing)

- AI text refinement / tone adjustment
- Personalization / learning
- Cross-platform (Windows, Linux)
- Settings window (Menu Bar dropdown is enough)
- App Store distribution
- Transcription history
- Commercial features / licensing (deferred to 2.0)
- Homebrew cask (future task)
