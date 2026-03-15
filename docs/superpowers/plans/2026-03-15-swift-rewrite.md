# Claude Talk Swift Rewrite — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite Claude Talk as a native macOS Swift app with whisper.cpp, Notch UI, and Menu Bar controls — zero dependencies for users.

**Architecture:** Single-process Swift macOS app. whisper.cpp vendored as C source with bridging header. AVFoundation for audio, CGEvent for hotkey capture and keyboard simulation, NSPanel for Notch overlay, NSStatusItem for Menu Bar.

**Tech Stack:** Swift 5.9+, whisper.cpp (C), Xcode 15+, macOS 14+ SDK, AVFoundation, CoreGraphics, AppKit

**Spec:** `docs/superpowers/specs/2026-03-15-notch-ui-swift-rewrite-design.md`

---

## File Structure

```
ClaudeTalk/
├── ClaudeTalk.xcodeproj
├── ClaudeTalk/
│   ├── App/
│   │   ├── AppDelegate.swift              — App lifecycle, menu bar setup, permission checks
│   │   ├── ClaudeTalkApp.swift            — @main entry point (NSApplication delegate wiring)
│   │   └── Info.plist                     — LSUIElement=true (no dock icon), permissions descriptions
│   ├── Audio/
│   │   ├── AudioEngine.swift              — AVFoundation mic recording, RMS calculation
│   │   └── AudioEngineTests.swift         — (in test target)
│   ├── Transcription/
│   │   ├── WhisperWrapper.swift           — Swift wrapper around whisper.cpp functions
│   │   ├── ModelManager.swift             — Download, cache, select Whisper models
│   │   └── ModelManagerTests.swift        — (in test target)
│   ├── Processing/
│   │   ├── PostProcessor.swift            — Filler word removal (regex rules)
│   │   └── PostProcessorTests.swift       — (in test target)
│   ├── Input/
│   │   ├── HotkeyManager.swift            — CGEvent tap for global hotkey capture
│   │   ├── InputSimulator.swift           — CGEvent Cmd+V paste with clipboard preservation
│   │   ├── TerminalDetector.swift         — NSWorkspace focused app check against whitelist
│   │   └── TerminalDetectorTests.swift    — (in test target)
│   ├── UI/
│   │   ├── NotchOverlay.swift             — NSPanel pill window, positioning, notch detection
│   │   ├── NotchContentView.swift         — Waveform/character animations, timer display
│   │   ├── WaveformView.swift             — Bars/Dots/Line waveform renderers
│   │   ├── CharacterView.swift            — 8-bit pixel character sprite animation
│   │   ├── MenuBarController.swift        — NSStatusItem, dropdown menu, settings bindings
│   │   └── OnboardingWindow.swift         — First-launch setup (model download, permissions, hotkey)
│   ├── Settings/
│   │   └── Settings.swift                 — UserDefaults wrapper, all app settings in one place
│   ├── Orchestrator/
│   │   └── RecordingOrchestrator.swift    — Coordinates the full pipeline: hotkey → record → transcribe → paste
│   └── Assets.xcassets/
│       ├── AppIcon.appiconset/            — App icon
│       └── Characters/                    — 8-bit pixel character PNGs (placeholder until assets arrive)
├── whisper.cpp/                           — Vendored whisper.cpp source (git submodule)
│   ├── whisper.h
│   ├── whisper.cpp
│   ├── ggml*.h / ggml*.c                 — ggml tensor library
│   └── ...
├── ClaudeTalkTests/
│   ├── PostProcessorTests.swift
│   ├── TerminalDetectorTests.swift
│   ├── SettingsTests.swift
│   └── ModelManagerTests.swift
└── ClaudeTalk-Bridging-Header.h           — #include "whisper.h"
```

---

## Chunk 1: Project Foundation

### Task 1: Create Xcode project and basic app shell

**Files:**
- Create: `ClaudeTalk/ClaudeTalk.xcodeproj`
- Create: `ClaudeTalk/ClaudeTalk/App/ClaudeTalkApp.swift`
- Create: `ClaudeTalk/ClaudeTalk/App/AppDelegate.swift`
- Create: `ClaudeTalk/ClaudeTalk/App/Info.plist`

- [ ] **Step 1: Create Xcode project**

Create a new macOS App project using Swift, AppKit (not SwiftUI), with the following settings:
- Product Name: `ClaudeTalk`
- Bundle Identifier: `com.claude-talk.app`
- Deployment Target: macOS 14.0
- Language: Swift

```bash
cd /Users/nelson/Desktop/AI/claude-talk
mkdir -p ClaudeTalk
```

Use `swift package init` is NOT suitable here — we need an Xcode project for whisper.cpp C compilation. Create the project manually or via Xcode CLI.

- [ ] **Step 2: Configure as Menu Bar-only app (no Dock icon)**

In `Info.plist`, set:
```xml
<key>LSUIElement</key>
<true/>
<key>NSMicrophoneUsageDescription</key>
<string>Claude Talk needs microphone access to record your voice for transcription.</string>
```

- [ ] **Step 3: Write AppDelegate with basic lifecycle**

```swift
// AppDelegate.swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Claude Talk")
        }
        print("Claude Talk launched")
    }
}
```

```swift
// ClaudeTalkApp.swift
import AppKit

@main
struct ClaudeTalkApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
```

- [ ] **Step 4: Build and run — verify menu bar icon appears**

```bash
xcodebuild -project ClaudeTalk.xcodeproj -scheme ClaudeTalk build
```

Expected: App launches, microphone icon appears in menu bar, no Dock icon.

- [ ] **Step 5: Commit**

```bash
git add ClaudeTalk/
git commit -m "feat: create Xcode project with menu bar app shell"
```

---

### Task 2: Vendor whisper.cpp and configure bridging header

**Files:**
- Create: `ClaudeTalk/whisper.cpp/` (git submodule)
- Create: `ClaudeTalk/ClaudeTalk-Bridging-Header.h`
- Create: `ClaudeTalk/ClaudeTalk/Transcription/WhisperBridge.h`

- [ ] **Step 1: Add whisper.cpp as git submodule**

```bash
cd /Users/nelson/Desktop/AI/claude-talk/ClaudeTalk
git submodule add https://github.com/ggerganov/whisper.cpp.git whisper.cpp
cd whisper.cpp
git checkout v1.7.3  # pin to a stable release
cd ..
```

- [ ] **Step 2: Create bridging header**

```c
// ClaudeTalk-Bridging-Header.h
#ifndef ClaudeTalk_Bridging_Header_h
#define ClaudeTalk_Bridging_Header_h

#include "whisper.cpp/whisper.h"

#endif
```

Configure in Xcode Build Settings:
- `Objective-C Bridging Header` = `ClaudeTalk-Bridging-Header.h`

- [ ] **Step 3: Add whisper.cpp source files to Xcode project**

Add the following files from `whisper.cpp/` to the Xcode project's Compile Sources:
- `whisper.cpp/whisper.cpp`
- `whisper.cpp/ggml/src/ggml.c`
- `whisper.cpp/ggml/src/ggml-alloc.c`
- `whisper.cpp/ggml/src/ggml-backend.c`
- `whisper.cpp/ggml/src/ggml-metal.m` (Apple Silicon Metal support)
- `whisper.cpp/ggml/src/ggml-quants.c`

Add compiler flags for these C/C++ sources:
- `-O3` optimization
- `-DGGML_USE_METAL` (enable Metal on Apple Silicon)

Link frameworks: `Accelerate.framework`, `Metal.framework`, `MetalKit.framework`

- [ ] **Step 4: Build to verify whisper.cpp compiles**

```bash
xcodebuild -project ClaudeTalk.xcodeproj -scheme ClaudeTalk build
```

Expected: Build succeeds with whisper.cpp symbols available.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "feat: vendor whisper.cpp as submodule with bridging header"
```

---

### Task 3: Settings manager

**Files:**
- Create: `ClaudeTalk/ClaudeTalk/Settings/Settings.swift`
- Create: `ClaudeTalk/ClaudeTalkTests/SettingsTests.swift`

- [ ] **Step 1: Write tests for Settings**

```swift
// SettingsTests.swift
import XCTest
@testable import ClaudeTalk

final class SettingsTests: XCTestCase {
    override func setUp() {
        // Use a separate UserDefaults suite for testing
        Settings.shared = Settings(defaults: UserDefaults(suiteName: "test")!)
    }

    override func tearDown() {
        UserDefaults(suiteName: "test")?.removePersistentDomain(forName: "test")
    }

    func testDefaultValues() {
        let s = Settings.shared
        XCTAssertEqual(s.hotkey, "fn")
        XCTAssertEqual(s.modelSize, "base")
        XCTAssertNil(s.language)
        XCTAssertTrue(s.removeFillerWords)
        XCTAssertEqual(s.accentColor, "white")
        XCTAssertEqual(s.waveformStyle, "bars")
        XCTAssertEqual(s.pillStyle, "solid")
        XCTAssertFalse(s.launchAtLogin)
    }

    func testPersistence() {
        let s = Settings.shared
        s.modelSize = "small"
        s.accentColor = "purple"
        let s2 = Settings(defaults: UserDefaults(suiteName: "test")!)
        XCTAssertEqual(s2.modelSize, "small")
        XCTAssertEqual(s2.accentColor, "purple")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project ClaudeTalk.xcodeproj -scheme ClaudeTalk
```

Expected: FAIL — `Settings` type not found.

- [ ] **Step 3: Implement Settings**

```swift
// Settings.swift
import Foundation

class Settings {
    static var shared = Settings(defaults: .standard)

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var hotkey: String {
        get { defaults.string(forKey: "hotkey") ?? "fn" }
        set { defaults.set(newValue, forKey: "hotkey") }
    }

    var modelSize: String {
        get { defaults.string(forKey: "modelSize") ?? "base" }
        set { defaults.set(newValue, forKey: "modelSize") }
    }

    var language: String? {
        get { defaults.string(forKey: "language") }
        set { defaults.set(newValue, forKey: "language") }
    }

    var terminalWhitelist: [String] {
        get { defaults.stringArray(forKey: "terminalWhitelist") ?? ["terminal", "iterm2", "ghostty", "kitty", "warp", "alacritty", "wezterm", "hyper"] }
        set { defaults.set(newValue, forKey: "terminalWhitelist") }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }

    var removeFillerWords: Bool {
        get { defaults.object(forKey: "removeFillerWords") == nil ? true : defaults.bool(forKey: "removeFillerWords") }
        set { defaults.set(newValue, forKey: "removeFillerWords") }
    }

    var accentColor: String {
        get { defaults.string(forKey: "accentColor") ?? "white" }
        set { defaults.set(newValue, forKey: "accentColor") }
    }

    var waveformStyle: String {
        get { defaults.string(forKey: "waveformStyle") ?? "bars" }
        set { defaults.set(newValue, forKey: "waveformStyle") }
    }

    var pillStyle: String {
        get { defaults.string(forKey: "pillStyle") ?? "solid" }
        set { defaults.set(newValue, forKey: "pillStyle") }
    }

    var promptHint: String {
        get { defaults.string(forKey: "promptHint") ?? "以下是中英文夹杂的内容。Contains both Chinese and English." }
        set { defaults.set(newValue, forKey: "promptHint") }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project ClaudeTalk.xcodeproj -scheme ClaudeTalk
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/Settings/ ClaudeTalk/ClaudeTalkTests/SettingsTests.swift
git commit -m "feat: add Settings manager with UserDefaults persistence"
```

---

### Task 4: Post-processor (filler word removal)

**Files:**
- Create: `ClaudeTalk/ClaudeTalk/Processing/PostProcessor.swift`
- Create: `ClaudeTalk/ClaudeTalkTests/PostProcessorTests.swift`

- [ ] **Step 1: Write tests for PostProcessor**

```swift
// PostProcessorTests.swift
import XCTest
@testable import ClaudeTalk

final class PostProcessorTests: XCTestCase {
    let processor = PostProcessor()

    func testRemoveEnglishFillers() {
        XCTAssertEqual(processor.removeFillers("um I think um we should"), "I think we should")
        XCTAssertEqual(processor.removeFillers("like you know it works"), "it works")
        XCTAssertEqual(processor.removeFillers("uh basically it's done"), "it's done")
    }

    func testRemoveChineseFillers() {
        XCTAssertEqual(processor.removeFillers("嗯我覺得啊這個就是可以"), "我覺得這個可以")
        XCTAssertEqual(processor.removeFillers("然後呃我們就是來做"), "我們來做")
    }

    func testPreserveValidWords() {
        // "like" in "likelihood" should NOT be removed
        XCTAssertEqual(processor.removeFillers("the likelihood is high"), "the likelihood is high")
        // "right" at end of sentence can be filler, but "right answer" is not
        XCTAssertEqual(processor.removeFillers("the right answer"), "the right answer")
    }

    func testEmptyAndNoFillers() {
        XCTAssertEqual(processor.removeFillers(""), "")
        XCTAssertEqual(processor.removeFillers("hello world"), "hello world")
    }

    func testCleanupExtraSpaces() {
        XCTAssertEqual(processor.removeFillers("um  um  hello"), "hello")
    }

    func testDisabledReturnsOriginal() {
        XCTAssertEqual(processor.process("um hello", enabled: false), "um hello")
        XCTAssertEqual(processor.process("um hello", enabled: true), "hello")
    }

    func testCustomDictionary() {
        let dict = ["克劳德": "Claude", "吉特": "Git", "皮埃": "PR"]
        XCTAssertEqual(processor.applyDictionary("用克劳德來寫吉特", dictionary: dict), "用Claude來寫Git")
        XCTAssertEqual(processor.applyDictionary("hello world", dictionary: dict), "hello world")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project ClaudeTalk.xcodeproj -scheme ClaudeTalk
```

Expected: FAIL — `PostProcessor` not found.

- [ ] **Step 3: Implement PostProcessor**

```swift
// PostProcessor.swift
import Foundation

struct PostProcessor {
    private let englishFillers = [
        "\\bum\\b", "\\buh\\b", "\\buh huh\\b", "\\byou know\\b",
        "\\bI mean\\b", "\\bbasically\\b", "\\bactually\\b",
        "\\bso yeah\\b"
    ]

    // "like" and "right" only removed when standalone (not part of compound)
    private let standaloneFillers = [
        "(?<![a-zA-Z])like(?![a-zA-Z])",
        "(?<=\\s)right(?=[\\s,.]|$)"
    ]

    private let chineseFillers = ["嗯", "啊", "呃", "齁", "那個", "就是", "然後", "對"]

    func removeFillers(_ text: String) -> String {
        var result = text

        for pattern in englishFillers + standaloneFillers {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
        }

        for filler in chineseFillers {
            result = result.replacingOccurrences(of: filler, with: "")
        }

        // Collapse multiple spaces into one, trim
        result = result.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }

    func applyDictionary(_ text: String, dictionary: [String: String]) -> String {
        var result = text
        for (wrong, correct) in dictionary {
            result = result.replacingOccurrences(of: wrong, with: correct)
        }
        return result
    }

    func process(_ text: String, enabled: Bool, dictionary: [String: String] = [:]) -> String {
        var result = text
        if enabled {
            result = removeFillers(result)
        }
        if !dictionary.isEmpty {
            result = applyDictionary(result, dictionary: dictionary)
        }
        return result
    }

    /// Load custom dictionary from ~/Library/Application Support/Claude Talk/dictionary.json
    static func loadDictionary() -> [String: String] {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let path = appSupport.appendingPathComponent("Claude Talk/dictionary.json")
        guard let data = try? Data(contentsOf: path),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            // Write default dictionary on first access
            let defaults: [String: String] = [
                "克劳德": "Claude", "吉特": "Git", "皮埃": "PR",
                "艾皮艾": "API", "蒂普洛伊": "deploy", "可米特": "commit",
                "普什": "push", "普爾": "pull"
            ]
            let dir = appSupport.appendingPathComponent("Claude Talk")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? JSONEncoder().encode(defaults).write(to: path)
            return defaults
        }
        return dict
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project ClaudeTalk.xcodeproj -scheme ClaudeTalk
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/Processing/ ClaudeTalk/ClaudeTalkTests/PostProcessorTests.swift
git commit -m "feat: add filler word removal post-processor"
```

---

### Task 5: Terminal detector

**Files:**
- Create: `ClaudeTalk/ClaudeTalk/Input/TerminalDetector.swift`
- Create: `ClaudeTalk/ClaudeTalkTests/TerminalDetectorTests.swift`

- [ ] **Step 1: Write tests for TerminalDetector**

```swift
// TerminalDetectorTests.swift
import XCTest
@testable import ClaudeTalk

final class TerminalDetectorTests: XCTestCase {
    func testDefaultWhitelist() {
        let detector = TerminalDetector(whitelist: nil)
        XCTAssertTrue(detector.isTerminal("Terminal"))
        XCTAssertTrue(detector.isTerminal("iTerm2"))
        XCTAssertTrue(detector.isTerminal("ghostty"))
        XCTAssertTrue(detector.isTerminal("Ghostty"))
        XCTAssertTrue(detector.isTerminal("kitty"))
        XCTAssertTrue(detector.isTerminal("Warp"))
        XCTAssertFalse(detector.isTerminal("Safari"))
        XCTAssertFalse(detector.isTerminal("Finder"))
    }

    func testCustomWhitelist() {
        let detector = TerminalDetector(whitelist: ["myterm"])
        XCTAssertTrue(detector.isTerminal("MyTerm"))
        XCTAssertFalse(detector.isTerminal("Terminal"))
    }

    func testCaseInsensitive() {
        let detector = TerminalDetector(whitelist: nil)
        XCTAssertTrue(detector.isTerminal("ITERM2"))
        XCTAssertTrue(detector.isTerminal("terminal"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement TerminalDetector**

```swift
// TerminalDetector.swift
import AppKit

struct TerminalDetector {
    static let defaultWhitelist = [
        "terminal", "iterm2", "ghostty", "kitty", "warp", "alacritty", "wezterm", "hyper"
    ]

    private let whitelist: Set<String>

    init(whitelist: [String]? = nil) {
        self.whitelist = Set((whitelist ?? Self.defaultWhitelist).map { $0.lowercased() })
    }

    func isTerminal(_ appName: String) -> Bool {
        whitelist.contains(appName.lowercased())
    }

    func isFocusedAppTerminal() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let name = app.localizedName ?? ""
        return isTerminal(name)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/Input/TerminalDetector.swift ClaudeTalk/ClaudeTalkTests/TerminalDetectorTests.swift
git commit -m "feat: add terminal detector with configurable whitelist"
```

---

## Chunk 2: Audio & Transcription

### Task 6: Audio engine (microphone recording)

**Files:**
- Create: `ClaudeTalk/ClaudeTalk/Audio/AudioEngine.swift`

- [ ] **Step 1: Implement AudioEngine**

```swift
// AudioEngine.swift
import AVFoundation
import Foundation

protocol AudioEngineDelegate: AnyObject {
    func audioEngine(_ engine: AudioEngine, didUpdateRMS rms: Float)
}

class AudioEngine {
    weak var delegate: AudioEngineDelegate?

    private let engine = AVAudioEngine()
    private var buffer = [Float]()
    private let sampleRate: Double = 16000
    private let lock = NSLock()

    var isRecording: Bool { engine.isRunning }

    func startRecording() throws {
        let inputNode = engine.inputNode
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

        buffer.removeAll()

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] pcmBuffer, _ in
            guard let self, let channelData = pcmBuffer.floatChannelData else { return }
            let frames = Int(pcmBuffer.frameLength)
            let data = Array(UnsafeBufferPointer(start: channelData[0], count: frames))

            self.lock.lock()
            self.buffer.append(contentsOf: data)
            self.lock.unlock()

            // Calculate RMS for UI
            let rms = Self.calculateRMS(data)
            DispatchQueue.main.async {
                self.delegate?.audioEngine(self, didUpdateRMS: rms)
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stopRecording() -> (samples: [Float], duration: Double)? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        let samples = buffer
        lock.unlock()

        guard !samples.isEmpty else { return nil }
        let duration = Double(samples.count) / sampleRate
        return (samples, duration)
    }

    static func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
}
```

- [ ] **Step 2: Manual test — build and verify no compilation errors**

```bash
xcodebuild -project ClaudeTalk.xcodeproj -scheme ClaudeTalk build
```

- [ ] **Step 3: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/Audio/
git commit -m "feat: add AudioEngine with AVFoundation mic recording and RMS"
```

---

### Task 7: Whisper Swift wrapper

**Files:**
- Create: `ClaudeTalk/ClaudeTalk/Transcription/WhisperWrapper.swift`

- [ ] **Step 1: Implement WhisperWrapper**

```swift
// WhisperWrapper.swift
import Foundation

class WhisperWrapper {
    private var context: OpaquePointer?

    init(modelPath: String) throws {
        var params = whisper_context_default_params()
        context = whisper_init_from_file_with_params(modelPath, params)
        guard context != nil else {
            throw WhisperError.modelLoadFailed
        }
    }

    deinit {
        if let ctx = context {
            whisper_free(ctx)
        }
    }

    func transcribe(samples: [Float], language: String? = nil, beamSize: Int32 = 5, promptHint: String? = nil) -> String {
        guard let ctx = context else { return "" }

        var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
        params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))
        params.beam_search.beam_size = beamSize
        params.print_progress = false
        params.print_timestamps = false

        // Run whisper_full inside withCString to keep pointers alive
        let runTranscription = { (langPtr: UnsafePointer<CChar>?, promptPtr: UnsafePointer<CChar>?) -> Int32 in
            var p = params
            p.language = langPtr
            p.initial_prompt = promptPtr
            return samples.withUnsafeBufferPointer { bufferPointer in
                whisper_full(ctx, p, bufferPointer.baseAddress, Int32(samples.count))
            }
        }

        let result: Int32
        let callWithPrompt = { (promptPtr: UnsafePointer<CChar>?) -> Int32 in
            if let lang = language {
                return lang.withCString { langPtr in runTranscription(langPtr, promptPtr) }
            } else {
                return runTranscription(nil, promptPtr)
            }
        }
        if let prompt = promptHint, !prompt.isEmpty {
            result = prompt.withCString { promptPtr in callWithPrompt(promptPtr) }
        } else {
            result = callWithPrompt(nil)
        }

        guard result == 0 else { return "" }

        let nSegments = whisper_full_n_segments(ctx)
        var text = ""
        for i in 0..<nSegments {
            if let cStr = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: cStr)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WhisperError: Error {
    case modelLoadFailed
}
```

- [ ] **Step 2: Build to verify compilation with whisper.cpp**

```bash
xcodebuild -project ClaudeTalk.xcodeproj -scheme ClaudeTalk build
```

Expected: Build succeeds. WhisperWrapper calls whisper.cpp C functions through bridging header.

- [ ] **Step 3: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/Transcription/WhisperWrapper.swift
git commit -m "feat: add Swift wrapper around whisper.cpp C API"
```

---

### Task 8: Model manager (download and cache)

**Files:**
- Create: `ClaudeTalk/ClaudeTalk/Transcription/ModelManager.swift`
- Create: `ClaudeTalk/ClaudeTalkTests/ModelManagerTests.swift`

- [ ] **Step 1: Write tests for ModelManager**

```swift
// ModelManagerTests.swift
import XCTest
@testable import ClaudeTalk

final class ModelManagerTests: XCTestCase {
    func testModelDirectory() {
        let manager = ModelManager()
        let dir = manager.modelsDirectory
        XCTAssertTrue(dir.path.contains("Application Support/Claude Talk/models"))
    }

    func testModelFilename() {
        let manager = ModelManager()
        XCTAssertEqual(manager.filename(for: "base"), "ggml-base.bin")
        XCTAssertEqual(manager.filename(for: "small"), "ggml-small.bin")
    }

    func testIsDownloadedReturnsFalseForMissing() {
        let manager = ModelManager()
        // Use a model name that definitely doesn't exist
        XCTAssertFalse(manager.isDownloaded("nonexistent-model"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

- [ ] **Step 3: Implement ModelManager**

```swift
// ModelManager.swift
import Foundation

class ModelManager {
    static let baseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

    var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Claude Talk/models")
    }

    func filename(for model: String) -> String {
        "ggml-\(model).bin"
    }

    func modelPath(for model: String) -> URL {
        modelsDirectory.appendingPathComponent(filename(for: model))
    }

    func isDownloaded(_ model: String) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: model).path)
    }

    private var progressObservation: NSKeyValueObservation?

    func download(_ model: String, progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        let url = URL(string: "\(Self.baseURL)/\(filename(for: model))")!
        let destination = modelPath(for: model)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            self?.progressObservation = nil  // Clean up observation
            if let error {
                completion(.failure(error))
                return
            }
            guard let tempURL else {
                completion(.failure(ModelError.downloadFailed))
                return
            }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
                completion(.success(destination))
            } catch {
                completion(.failure(error))
            }
        }

        // Store observation to prevent deallocation
        progressObservation = task.progress.observe(\.fractionCompleted) { taskProgress, _ in
            DispatchQueue.main.async {
                progress(taskProgress.fractionCompleted)
            }
        }

        task.resume()
    }
}

enum ModelError: Error {
    case downloadFailed
}
```

- [ ] **Step 4: Run tests to verify they pass**

- [ ] **Step 5: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/Transcription/ModelManager.swift ClaudeTalk/ClaudeTalkTests/ModelManagerTests.swift
git commit -m "feat: add ModelManager for Whisper model download and caching"
```

---

### Task 9: Input simulator (clipboard paste)

**Files:**
- Create: `ClaudeTalk/ClaudeTalk/Input/InputSimulator.swift`

- [ ] **Step 1: Implement InputSimulator**

```swift
// InputSimulator.swift
import AppKit
import CoreGraphics

struct InputSimulator {
    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let originalContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        simulateCmdV()

        // Restore clipboard after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            pasteboard.clearContents()
            if let original = originalContents {
                pasteboard.setString(original, forType: .string)
            }
        }
    }

    private static func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)  // 0x09 = 'v'
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
xcodebuild -project ClaudeTalk.xcodeproj -scheme ClaudeTalk build
```

- [ ] **Step 3: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/Input/InputSimulator.swift
git commit -m "feat: add InputSimulator for CGEvent Cmd+V paste"
```

---

### Task 10: Hotkey manager (global key capture)

**Files:**
- Create: `ClaudeTalk/ClaudeTalk/Input/HotkeyManager.swift`

- [ ] **Step 1: Implement HotkeyManager**

```swift
// HotkeyManager.swift
import CoreGraphics
import Foundation

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyDidPress()
    func hotkeyDidRelease()
}

class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var targetKeyCode: CGKeyCode

    // Key codes for supported hotkeys
    static let keyCodes: [String: CGKeyCode] = [
        "fn": 0x3F,
        "left_option": 0x3A,
        "right_option": 0x3D,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x63,
        "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F
    ]

    init(hotkey: String = "fn") {
        targetKeyCode = Self.keyCodes[hotkey] ?? 0x3F
    }

    func updateHotkey(_ hotkey: String) {
        targetKeyCode = Self.keyCodes[hotkey] ?? 0x3F
    }

    func start() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
    }

    private var isPressed = false

    private func handleEvent(type: CGEventType, event: CGEvent) {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .flagsChanged {
            // For modifier keys (fn, option), flagsChanged fires for both press and release
            if keyCode == targetKeyCode {
                if !isPressed {
                    isPressed = true
                    DispatchQueue.main.async { self.delegate?.hotkeyDidPress() }
                } else {
                    isPressed = false
                    DispatchQueue.main.async { self.delegate?.hotkeyDidRelease() }
                }
            }
        } else if type == .keyDown && keyCode == targetKeyCode && !isPressed {
            isPressed = true
            DispatchQueue.main.async { self.delegate?.hotkeyDidPress() }
        } else if type == .keyUp && keyCode == targetKeyCode && isPressed {
            isPressed = false
            DispatchQueue.main.async { self.delegate?.hotkeyDidRelease() }
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
xcodebuild -project ClaudeTalk.xcodeproj -scheme ClaudeTalk build
```

- [ ] **Step 3: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/Input/HotkeyManager.swift
git commit -m "feat: add HotkeyManager with CGEvent global hotkey capture"
```

---

## Chunk 3: Notch UI

### Task 11: Notch overlay window (NSPanel shell)

**Files:**
- Create: `ClaudeTalk/ClaudeTalk/UI/NotchOverlay.swift`

- [ ] **Step 1: Implement NotchOverlay**

```swift
// NotchOverlay.swift
import AppKit

enum NotchState {
    case idle
    case recording
    case transcribing
    case success
    case error
    case discarded
}

class NotchOverlay {
    private var panel: NSPanel?
    private var contentView: NotchContentView?

    private let pillWidth: CGFloat = 280
    private let pillHeight: CGFloat = 36
    private let cornerRadius: CGFloat = 20
    private let animationDuration: TimeInterval = 0.3

    var state: NotchState = .idle {
        didSet { handleStateChange(from: oldValue, to: state) }
    }

    private var hasNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }

    private func createPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false

        let content = NotchContentView(frame: NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        content.layer?.cornerRadius = cornerRadius
        content.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]  // bottom corners only (flipped)
        panel.contentView = content
        self.contentView = content

        computePositions()
        panel.setFrameOrigin(restPosition)
        return panel
    }

    private func computePositions() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let x = screenFrame.midX - pillWidth / 2
        if hasNotch {
            showPosition = NSPoint(x: x, y: screenFrame.maxY - screen.safeAreaInsets.top - pillHeight)
            restPosition = NSPoint(x: x, y: screenFrame.maxY - screen.safeAreaInsets.top)  // hidden above
        } else {
            showPosition = NSPoint(x: x, y: screenFrame.maxY - pillHeight - 4)
            restPosition = NSPoint(x: x, y: screenFrame.maxY)  // hidden above
        }
    }

    /// Apply frosted glass or solid black pill style
    func applyPillStyle(_ style: String) {
        guard let content = contentView else { return }
        content.subviews.filter { $0 is NSVisualEffectView }.forEach { $0.removeFromSuperview() }

        if style == "frosted" {
            let effectView = NSVisualEffectView(frame: content.bounds)
            effectView.material = .dark
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = cornerRadius
            effectView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            content.addSubview(effectView, positioned: .below, relativeTo: content.subviews.first)
            content.layer?.backgroundColor = NSColor.clear.cgColor
        } else {
            content.layer?.backgroundColor = NSColor.black.cgColor
        }
    }

    func updateRMS(_ rms: Float) {
        contentView?.updateRMS(rms)
    }

    private func handleStateChange(from: NotchState, to: NotchState) {
        switch to {
        case .idle:
            hidePanel()
        case .recording:
            showPanel()
            contentView?.showRecording()
        case .transcribing:
            contentView?.showTranscribing()
        case .success:
            NSSound(named: "Pop")?.play()
            hidePanel()
        case .error:
            NSSound(named: "Basso")?.play()
            hidePanel()
        case .discarded:
            hidePanel(animated: false)
        }
    }

    private var restPosition: NSPoint = .zero  // hidden (above screen)
    private var showPosition: NSPoint = .zero  // visible (below notch)

    private func showPanel() {
        if panel == nil {
            panel = createPanel()
        }
        guard let panel else { return }

        // Start hidden above the notch
        panel.setFrameOrigin(restPosition)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        // Slide down
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animationDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(showPosition)
        }
    }

    private func hidePanel(animated: Bool = true) {
        guard let panel else { return }

        if !animated {
            panel.setFrameOrigin(restPosition)
            panel.orderOut(nil)
            return
        }

        // Slide up into notch
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = animated ? animationDuration : 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(restPosition)
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
xcodebuild -project ClaudeTalk.xcodeproj -scheme ClaudeTalk build
```

- [ ] **Step 3: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/UI/NotchOverlay.swift
git commit -m "feat: add NotchOverlay NSPanel with notch detection and animations"
```

---

### Task 12: Notch content view (waveform + timer layout)

**Files:**
- Create: `ClaudeTalk/ClaudeTalk/UI/NotchContentView.swift`
- Create: `ClaudeTalk/ClaudeTalk/UI/WaveformView.swift`

- [ ] **Step 1: Implement WaveformView**

```swift
// WaveformView.swift
import AppKit

enum WaveformStyle: String, CaseIterable {
    case bars, dots, line
}

class WaveformView: NSView {
    var style: WaveformStyle = .bars { didSet { needsDisplay = true } }
    var accentColor: NSColor = .white { didSet { needsDisplay = true } }
    var rms: Float = 0 { didSet { needsDisplay = true } }

    private let barCount = 7

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        accentColor.setFill()

        switch style {
        case .bars:
            drawBars(in: bounds, context: context)
        case .dots:
            drawDots(in: bounds, context: context)
        case .line:
            drawLine(in: bounds, context: context)
        }
    }

    private func drawBars(in rect: NSRect, context: CGContext) {
        let barWidth: CGFloat = 3
        let gap: CGFloat = 2
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
        let startX = (rect.width - totalWidth) / 2

        for i in 0..<barCount {
            let x = startX + CGFloat(i) * (barWidth + gap)
            // Vary height per bar using a simple pattern + RMS
            let variation = Float(abs(i - barCount / 2)) / Float(barCount / 2)
            let heightRatio = max(0.15, CGFloat(rms * 3) * CGFloat(1.0 - variation * 0.5))
            let barHeight = min(rect.height * 0.9, rect.height * heightRatio)
            let y = (rect.height - barHeight) / 2
            context.fill(CGRect(x: x, y: y, width: barWidth, height: barHeight))
        }
    }

    private func drawDots(in rect: NSRect, context: CGContext) {
        let dotCount = 5
        let maxRadius: CGFloat = 4
        let gap: CGFloat = 6
        let totalWidth = CGFloat(dotCount) * maxRadius * 2 + CGFloat(dotCount - 1) * gap
        let startX = (rect.width - totalWidth) / 2

        for i in 0..<dotCount {
            let variation = Float(abs(i - dotCount / 2)) / Float(dotCount / 2)
            let sizeRatio = max(0.3, CGFloat(rms * 3) * CGFloat(1.0 - variation * 0.5))
            let radius = maxRadius * min(1.0, sizeRatio)
            let x = startX + CGFloat(i) * (maxRadius * 2 + gap) + maxRadius
            let y = rect.midY
            context.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
    }

    private func drawLine(in rect: NSRect, context: CGContext) {
        let path = NSBezierPath()
        let points = 20
        let step = rect.width / CGFloat(points - 1)

        path.move(to: NSPoint(x: 0, y: rect.midY))
        for i in 0..<points {
            let x = CGFloat(i) * step
            let sine = sin(CGFloat(i) * 0.8 + CGFloat(CACurrentMediaTime() * 3))
            let amplitude = rect.height * 0.3 * CGFloat(rms * 3)
            let y = rect.midY + sine * amplitude
            path.line(to: NSPoint(x: x, y: y))
        }

        accentColor.setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
```

- [ ] **Step 2: Implement NotchContentView**

```swift
// NotchContentView.swift
import AppKit

class NotchContentView: NSView {
    private let waveformView = WaveformView()
    private let characterView = CharacterView()
    private let timerLabel = NSTextField(labelWithString: "0:00")
    private var timer: Timer?
    private var recordingStartTime: Date?

    private var useCharacter: Bool = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Waveform — left side, avoiding center (notch camera area)
        waveformView.frame = NSRect(x: 16, y: 4, width: 80, height: 28)
        addSubview(waveformView)

        // Character view — same position, hidden by default
        characterView.frame = NSRect(x: 26, y: 4, width: 28, height: 28)
        characterView.isHidden = true
        addSubview(characterView)

        // Timer — right side
        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        timerLabel.textColor = .white
        timerLabel.frame = NSRect(x: bounds.width - 60, y: 8, width: 50, height: 20)
        timerLabel.alignment = .right
        addSubview(timerLabel)
    }

    func configure(waveformStyle: String, accentColor: NSColor) {
        if ["cat", "rabbit", "dog"].contains(waveformStyle) {
            useCharacter = true
            waveformView.isHidden = true
            characterView.isHidden = false
            characterView.character = waveformStyle
        } else {
            useCharacter = false
            waveformView.isHidden = false
            characterView.isHidden = true
            waveformView.style = WaveformStyle(rawValue: waveformStyle) ?? .bars
        }
        waveformView.accentColor = accentColor
        timerLabel.textColor = accentColor
    }

    func updateRMS(_ rms: Float) {
        waveformView.rms = rms
        if useCharacter {
            characterView.updateRMS(rms)
        }
    }

    func showRecording() {
        recordingStartTime = Date()
        timerLabel.stringValue = "0:00"
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
    }

    func showTranscribing() {
        timer?.invalidate()
        timer = nil
        if useCharacter {
            characterView.showThinking()
        } else {
            // Show pulsing dots
            waveformView.style = .dots
            waveformView.rms = 0.2  // gentle pulse
        }
    }

    private func updateTimer() {
        guard let start = recordingStartTime else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        timerLabel.stringValue = String(format: "%d:%02d", minutes, seconds)
    }
}
```

- [ ] **Step 3: Build to verify compilation**

```bash
xcodebuild -project ClaudeTalk.xcodeproj -scheme ClaudeTalk build
```

- [ ] **Step 4: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/UI/NotchContentView.swift ClaudeTalk/ClaudeTalk/UI/WaveformView.swift
git commit -m "feat: add NotchContentView with waveform styles and timer"
```

---

### Task 13: Character view (8-bit pixel sprite animation)

**Files:**
- Create: `ClaudeTalk/ClaudeTalk/UI/CharacterView.swift`

- [ ] **Step 1: Implement CharacterView**

```swift
// CharacterView.swift
import AppKit

class CharacterView: NSView {
    // Frame names: {character}_closed, {character}_small, {character}_open, {character}_thinking
    enum MouthState: Int {
        case closed = 0, small = 1, open = 2, thinking = 3
    }

    var character: String = "cat" {
        didSet { loadSprites() }
    }

    private var sprites: [NSImage] = []
    private var currentFrame: MouthState = .closed
    private var isThinking = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        loadSprites()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadSprites()
    }

    private func loadSprites() {
        sprites = (0..<4).compactMap { frameIndex in
            // Look for: cat_0, cat_1, cat_2, cat_3 in assets
            let name = "\(character)_\(frameIndex)"
            if let image = NSImage(named: name) {
                return image
            }
            // Placeholder: colored square if asset not found
            return createPlaceholder(frameIndex: frameIndex)
        }
        needsDisplay = true
    }

    private func createPlaceholder(frameIndex: Int) -> NSImage {
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size)
        image.lockFocus()
        let gray = CGFloat(frameIndex) * 0.2 + 0.3
        NSColor(white: gray, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    func updateRMS(_ rms: Float) {
        guard !isThinking else { return }
        if rms < 0.01 {
            currentFrame = .closed
        } else if rms < 0.05 {
            currentFrame = .small
        } else {
            currentFrame = .open
        }
        needsDisplay = true
    }

    func showThinking() {
        isThinking = true
        currentFrame = .thinking
        needsDisplay = true
    }

    func reset() {
        isThinking = false
        currentFrame = .closed
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard currentFrame.rawValue < sprites.count else { return }
        let sprite = sprites[currentFrame.rawValue]

        // Draw pixel art without antialiasing to keep crisp edges
        guard let context = NSGraphicsContext.current else { return }
        context.imageInterpolation = .none

        sprite.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
xcodebuild -project ClaudeTalk.xcodeproj -scheme ClaudeTalk build
```

- [ ] **Step 3: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/UI/CharacterView.swift
git commit -m "feat: add CharacterView for 8-bit pixel sprite animation"
```

---

## Chunk 4: Menu Bar & Orchestration

### Task 14: Menu Bar controller

**Files:**
- Create: `ClaudeTalk/ClaudeTalk/UI/MenuBarController.swift`

- [ ] **Step 1: Implement MenuBarController**

```swift
// MenuBarController.swift
import AppKit

protocol MenuBarDelegate: AnyObject {
    func menuBarDidChangeSettings()
}

class MenuBarController {
    weak var delegate: MenuBarDelegate?

    private var statusItem: NSStatusItem?
    private let settings = Settings.shared

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Claude Talk")

        statusItem?.menu = buildMenu()
    }

    func showPermissionWarning() {
        statusItem?.button?.image = NSImage(systemSymbolName: "mic.badge.xmark", accessibilityDescription: "Claude Talk - Permission needed")
    }

    func clearPermissionWarning() {
        statusItem?.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Claude Talk")
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Header
        let header = NSMenuItem(title: "Claude Talk", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())

        // Hotkey submenu
        let hotkeyItem = NSMenuItem(title: "Hotkey: \(settings.hotkey)", action: nil, keyEquivalent: "")
        let hotkeyMenu = NSMenu()
        for key in ["fn", "left_option", "right_option", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12"] {
            let item = NSMenuItem(title: key, action: #selector(changeHotkey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            if key == settings.hotkey { item.state = .on }
            hotkeyMenu.addItem(item)
        }
        hotkeyItem.submenu = hotkeyMenu
        menu.addItem(hotkeyItem)

        // Model submenu
        let modelItem = NSMenuItem(title: "Model: \(settings.modelSize)", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        for model in ["tiny", "base", "small", "medium"] {
            let item = NSMenuItem(title: model, action: #selector(changeModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model
            if model == settings.modelSize { item.state = .on }
            modelMenu.addItem(item)
        }
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        // Language submenu
        let langItem = NSMenuItem(title: "Language: \(settings.language ?? "Auto")", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        let languages = [("Auto", nil as String?), ("English", "en"), ("中文", "zh"), ("日本語", "ja"), ("한국어", "ko"), ("Español", "es")]
        for (name, code) in languages {
            let item = NSMenuItem(title: name, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            if code == settings.language || (code == nil && settings.language == nil) { item.state = .on }
            langMenu.addItem(item)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        menu.addItem(NSMenuItem.separator())

        // Appearance submenu
        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu()

        // Accent Color
        let colorItem = NSMenuItem(title: "Accent Color", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        for color in ["white", "purple", "cyan", "green", "orange", "pink"] {
            let item = NSMenuItem(title: color.capitalized, action: #selector(changeAccentColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = color
            if color == settings.accentColor { item.state = .on }
            colorMenu.addItem(item)
        }
        colorItem.submenu = colorMenu
        appearanceMenu.addItem(colorItem)

        // Waveform Style
        let waveItem = NSMenuItem(title: "Waveform Style", action: nil, keyEquivalent: "")
        let waveMenu = NSMenu()
        for style in ["bars", "dots", "line", "cat", "rabbit", "dog"] {
            let icon: String
            switch style {
            case "cat": icon = "🐱 "
            case "rabbit": icon = "🐰 "
            case "dog": icon = "🐶 "
            default: icon = ""
            }
            let item = NSMenuItem(title: "\(icon)\(style.capitalized)", action: #selector(changeWaveformStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style
            if style == settings.waveformStyle { item.state = .on }
            waveMenu.addItem(item)
        }
        waveItem.submenu = waveMenu
        appearanceMenu.addItem(waveItem)

        // Pill Style
        let pillItem = NSMenuItem(title: "Pill Style", action: nil, keyEquivalent: "")
        let pillMenu = NSMenu()
        for style in ["solid", "frosted"] {
            let item = NSMenuItem(title: style == "solid" ? "Solid Black" : "Frosted Glass", action: #selector(changePillStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style
            if style == settings.pillStyle { item.state = .on }
            pillMenu.addItem(item)
        }
        pillItem.submenu = pillMenu
        appearanceMenu.addItem(pillItem)

        appearanceItem.submenu = appearanceMenu
        menu.addItem(appearanceItem)

        menu.addItem(NSMenuItem.separator())

        // Toggles
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = settings.launchAtLogin ? .on : .off
        menu.addItem(launchItem)

        let fillerItem = NSMenuItem(title: "Remove Filler Words", action: #selector(toggleFillerWords(_:)), keyEquivalent: "")
        fillerItem.target = self
        fillerItem.state = settings.removeFillerWords ? .on : .off
        menu.addItem(fillerItem)

        menu.addItem(NSMenuItem.separator())

        // About & Quit
        menu.addItem(NSMenuItem(title: "About Claude Talk", action: #selector(showAbout(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    // MARK: - Actions

    @objc private func changeHotkey(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        settings.hotkey = key
        rebuildMenu()
        delegate?.menuBarDidChangeSettings()
    }

    @objc private func changeModel(_ sender: NSMenuItem) {
        guard let model = sender.representedObject as? String else { return }
        settings.modelSize = model
        rebuildMenu()
        delegate?.menuBarDidChangeSettings()
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        settings.language = sender.representedObject as? String
        rebuildMenu()
        delegate?.menuBarDidChangeSettings()
    }

    @objc private func changeAccentColor(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? String else { return }
        settings.accentColor = color
        rebuildMenu()
        delegate?.menuBarDidChangeSettings()
    }

    @objc private func changeWaveformStyle(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? String else { return }
        settings.waveformStyle = style
        rebuildMenu()
        delegate?.menuBarDidChangeSettings()
    }

    @objc private func changePillStyle(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? String else { return }
        settings.pillStyle = style
        rebuildMenu()
        delegate?.menuBarDidChangeSettings()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        settings.launchAtLogin.toggle()
        rebuildMenu()
        delegate?.menuBarDidChangeSettings()
    }

    @objc private func toggleFillerWords(_ sender: NSMenuItem) {
        settings.removeFillerWords.toggle()
        rebuildMenu()
        delegate?.menuBarDidChangeSettings()
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    private func rebuildMenu() {
        statusItem?.menu = buildMenu()
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
xcodebuild -project ClaudeTalk.xcodeproj -scheme ClaudeTalk build
```

- [ ] **Step 3: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/UI/MenuBarController.swift
git commit -m "feat: add MenuBarController with all settings submenus"
```

---

### Task 15: Recording orchestrator (full pipeline)

**Files:**
- Create: `ClaudeTalk/ClaudeTalk/Orchestrator/RecordingOrchestrator.swift`

- [ ] **Step 1: Implement RecordingOrchestrator**

```swift
// RecordingOrchestrator.swift
import Foundation

class RecordingOrchestrator: HotkeyManagerDelegate, AudioEngineDelegate {
    private let audioEngine = AudioEngine()
    private let hotkeyManager: HotkeyManager
    private let notchOverlay = NotchOverlay()
    private let postProcessor = PostProcessor()
    private let terminalDetector: TerminalDetector
    private let settings = Settings.shared

    private var whisper: WhisperWrapper?
    private let modelManager = ModelManager()

    private var isTranscribing = false

    init() {
        hotkeyManager = HotkeyManager(hotkey: settings.hotkey)
        terminalDetector = TerminalDetector(whitelist: settings.terminalWhitelist)
        audioEngine.delegate = self
        hotkeyManager.delegate = self
    }

    func start() {
        loadModel()
        guard hotkeyManager.start() else {
            print("Failed to start hotkey capture. Check Accessibility permissions.")
            return
        }
        print("Claude Talk ready. Hold \(settings.hotkey) to speak.")
    }

    func stop() {
        hotkeyManager.stop()
    }

    func reloadSettings() {
        hotkeyManager.updateHotkey(settings.hotkey)
        // Reload model if changed
        loadModel()
        // Update notch appearance
        updateNotchAppearance()
    }

    private func loadModel() {
        let modelPath = modelManager.modelPath(for: settings.modelSize)
        guard modelManager.isDownloaded(settings.modelSize) else {
            print("Model \(settings.modelSize) not downloaded yet.")
            return
        }
        do {
            whisper = try WhisperWrapper(modelPath: modelPath.path)
            print("Loaded Whisper \(settings.modelSize) model.")
        } catch {
            print("Failed to load model: \(error)")
        }
    }

    private func updateNotchAppearance() {
        // Apply current appearance settings to notch overlay
        let color = accentNSColor(from: settings.accentColor)
        notchOverlay.contentView?.configure(waveformStyle: settings.waveformStyle, accentColor: color)
    }

    private func accentNSColor(from name: String) -> NSColor {
        switch name {
        case "purple": return NSColor(red: 0.66, green: 0.33, blue: 0.97, alpha: 1)
        case "cyan":   return NSColor(red: 0.02, green: 0.71, blue: 0.83, alpha: 1)
        case "green":  return NSColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1)
        case "orange": return NSColor(red: 0.98, green: 0.45, blue: 0.09, alpha: 1)
        case "pink":   return NSColor(red: 0.93, green: 0.30, blue: 0.60, alpha: 1)
        default:       return .white
        }
    }

    // MARK: - HotkeyManagerDelegate

    func hotkeyDidPress() {
        guard !isTranscribing else { return }
        guard terminalDetector.isFocusedAppTerminal() else { return }

        do {
            try audioEngine.startRecording()
            updateNotchAppearance()
            notchOverlay.state = .recording
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func hotkeyDidRelease() {
        guard audioEngine.isRecording else { return }

        guard let result = audioEngine.stopRecording() else {
            notchOverlay.state = .discarded
            return
        }

        // Check minimum duration
        guard result.duration >= 0.3 else {
            notchOverlay.state = .discarded
            return
        }

        // Check RMS threshold
        let rms = AudioEngine.calculateRMS(result.samples)
        guard rms > 0.01 else {
            notchOverlay.state = .discarded
            return
        }

        // Transcribe
        notchOverlay.state = .transcribing
        isTranscribing = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let whisper = self.whisper else {
                DispatchQueue.main.async {
                    self?.notchOverlay.state = .error
                    self?.isTranscribing = false
                }
                return
            }

            #if arch(arm64)
            let beamSize: Int32 = 5
            #else
            let beamSize: Int32 = 3  // Reduce for Intel Macs
            #endif
            let text = whisper.transcribe(
                samples: result.samples,
                language: self.settings.language,
                beamSize: beamSize,
                promptHint: self.settings.promptHint
            )

            let dictionary = PostProcessor.loadDictionary()
            let processed = self.postProcessor.process(text, enabled: self.settings.removeFillerWords, dictionary: dictionary)

            DispatchQueue.main.async {
                if processed.isEmpty {
                    self.notchOverlay.state = .error
                } else if self.terminalDetector.isFocusedAppTerminal() {
                    InputSimulator.paste(processed)
                    self.notchOverlay.state = .success
                    print(">> \(processed)")
                } else {
                    print("Skipped: terminal not focused")
                    self.notchOverlay.state = .error
                }
                self.isTranscribing = false
            }
        }
    }

    // MARK: - AudioEngineDelegate

    func audioEngine(_ engine: AudioEngine, didUpdateRMS rms: Float) {
        notchOverlay.updateRMS(rms)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
xcodebuild -project ClaudeTalk.xcodeproj -scheme ClaudeTalk build
```

- [ ] **Step 3: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/Orchestrator/
git commit -m "feat: add RecordingOrchestrator coordinating full pipeline"
```

---

### Task 16: Wire everything in AppDelegate

**Files:**
- Modify: `ClaudeTalk/ClaudeTalk/App/AppDelegate.swift`

- [ ] **Step 1: Update AppDelegate to wire all components**

```swift
// AppDelegate.swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, MenuBarDelegate {
    private let menuBar = MenuBarController()
    private let orchestrator = RecordingOrchestrator()
    private let modelManager = ModelManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check accessibility
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            menuBar.showPermissionWarning()
        }

        menuBar.delegate = self
        menuBar.setup()

        // Check if model is downloaded, if not trigger download
        let settings = Settings.shared
        if modelManager.isDownloaded(settings.modelSize) {
            orchestrator.start()
        } else {
            downloadModel(settings.modelSize)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        orchestrator.stop()
    }

    func menuBarDidChangeSettings() {
        orchestrator.reloadSettings()
    }

    private func downloadModel(_ model: String) {
        print("Downloading Whisper \(model) model...")
        modelManager.download(model, progress: { progress in
            print("Download: \(Int(progress * 100))%")
        }, completion: { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("Model downloaded.")
                    self?.orchestrator.start()
                case .failure(let error):
                    print("Download failed: \(error)")
                }
            }
        })
    }
}
```

- [ ] **Step 2: Build and run full app**

```bash
xcodebuild -project ClaudeTalk.xcodeproj -scheme ClaudeTalk build
```

Expected: App builds successfully with all components wired together.

- [ ] **Step 3: Manual integration test**

Launch the app. Verify:
1. Menu bar icon appears
2. Accessibility permission is requested
3. Model downloads (first launch)
4. Hold hotkey → notch UI appears with waveform
5. Release → text transcribed and pasted into terminal

- [ ] **Step 4: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/App/AppDelegate.swift
git commit -m "feat: wire all components in AppDelegate for full app flow"
```

---

### Task 16.5: Onboarding window (first launch)

**Files:**
- Create: `ClaudeTalk/ClaudeTalk/UI/OnboardingWindow.swift`

- [ ] **Step 1: Implement OnboardingWindow**

```swift
// OnboardingWindow.swift
import AppKit

protocol OnboardingDelegate: AnyObject {
    func onboardingDidComplete()
}

class OnboardingWindow: NSWindowController {
    weak var onboardingDelegate: OnboardingDelegate?

    private let modelManager = ModelManager()
    private let settings = Settings.shared

    private var progressBar: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var continueButton: NSButton!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Talk Setup"
        window.center()
        self.init(window: window)
        setupUI()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "Welcome to Claude Talk")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.frame = NSRect(x: 40, y: 200, width: 320, height: 30)
        contentView.addSubview(titleLabel)

        statusLabel = NSTextField(labelWithString: "Downloading Whisper model...")
        statusLabel.frame = NSRect(x: 40, y: 160, width: 320, height: 20)
        statusLabel.font = .systemFont(ofSize: 13)
        contentView.addSubview(statusLabel)

        progressBar = NSProgressIndicator(frame: NSRect(x: 40, y: 130, width: 320, height: 20))
        progressBar.style = .bar
        progressBar.minValue = 0
        progressBar.maxValue = 1
        contentView.addSubview(progressBar)

        continueButton = NSButton(title: "Continue", target: self, action: #selector(didTapContinue))
        continueButton.frame = NSRect(x: 270, y: 20, width: 100, height: 32)
        continueButton.bezelStyle = .rounded
        continueButton.isEnabled = false
        contentView.addSubview(continueButton)
    }

    func startSetup() {
        showWindow(nil)
        downloadModel()
    }

    private func downloadModel() {
        let model = settings.modelSize
        if modelManager.isDownloaded(model) {
            onDownloadComplete()
            return
        }

        modelManager.download(model, progress: { [weak self] progress in
            self?.progressBar.doubleValue = progress
            self?.statusLabel.stringValue = "Downloading Whisper \(model) model... \(Int(progress * 100))%"
        }, completion: { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.onDownloadComplete()
                case .failure(let error):
                    self?.statusLabel.stringValue = "Download failed: \(error.localizedDescription)"
                }
            }
        })
    }

    private func onDownloadComplete() {
        statusLabel.stringValue = "Model ready. Grant permissions and you're all set!"
        progressBar.doubleValue = 1
        continueButton.isEnabled = true

        // Trigger Accessibility permission prompt
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc private func didTapContinue() {
        close()
        onboardingDelegate?.onboardingDidComplete()
    }
}
```

- [ ] **Step 2: Update AppDelegate to show onboarding on first launch**

In `AppDelegate.applicationDidFinishLaunching`, check if model is downloaded:
- If NOT: show `OnboardingWindow` instead of starting orchestrator directly
- If YES: start orchestrator immediately (returning user)

Add `OnboardingDelegate` conformance to AppDelegate:
```swift
func onboardingDidComplete() {
    orchestrator.start()
}
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -project ClaudeTalk.xcodeproj -scheme ClaudeTalk build
```

- [ ] **Step 4: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/UI/OnboardingWindow.swift ClaudeTalk/ClaudeTalk/App/AppDelegate.swift
git commit -m "feat: add onboarding window for first-launch setup"
```

---

## Chunk 5: Polish & Distribution

### Task 17: App icon and Info.plist finalization

**Files:**
- Modify: `ClaudeTalk/ClaudeTalk/Assets.xcassets/AppIcon.appiconset/`
- Modify: `ClaudeTalk/ClaudeTalk/App/Info.plist`

- [ ] **Step 1: Create placeholder app icon**

Create a simple app icon (microphone on dark background). Use a 1024x1024 PNG.
For now, create a placeholder using macOS built-in `sips` to generate a solid color icon:

```bash
# Placeholder — replace with proper icon later
mkdir -p ClaudeTalk/ClaudeTalk/Assets.xcassets/AppIcon.appiconset
```

Add `Contents.json` for the icon set pointing to the placeholder.

- [ ] **Step 2: Finalize Info.plist**

Ensure Info.plist contains:
```xml
<key>LSUIElement</key>
<true/>
<key>NSMicrophoneUsageDescription</key>
<string>Claude Talk needs microphone access to record your voice for transcription.</string>
<key>CFBundleShortVersionString</key>
<string>1.0.0</string>
<key>CFBundleName</key>
<string>Claude Talk</string>
<key>NSHumanReadableCopyright</key>
<string>MIT License</string>
```

- [ ] **Step 3: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/Assets.xcassets/ ClaudeTalk/ClaudeTalk/App/Info.plist
git commit -m "feat: add app icon placeholder and finalize Info.plist"
```

---

### Task 18: Build configuration for universal binary

**Files:**
- Modify: Xcode project build settings

- [ ] **Step 1: Configure universal binary build**

In Xcode project build settings:
- `ARCHS` = `$(ARCHS_STANDARD)` (includes arm64 + x86_64)
- `BUILD_LIBRARY_FOR_DISTRIBUTION` = `YES`
- `MACOSX_DEPLOYMENT_TARGET` = `14.0`

- [ ] **Step 2: Create build script**

```bash
# build.sh
#!/bin/bash
set -e

SCHEME="ClaudeTalk"
BUILD_DIR="build"

xcodebuild -project ClaudeTalk.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$BUILD_DIR/ClaudeTalk.xcarchive" \
  archive

xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/ClaudeTalk.xcarchive" \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath "$BUILD_DIR/export"

echo "Build complete: $BUILD_DIR/export/Claude Talk.app"
```

- [ ] **Step 3: Create DMG packaging script**

```bash
# package-dmg.sh
#!/bin/bash
set -e

APP_PATH="build/export/Claude Talk.app"
DMG_NAME="ClaudeTalk-$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString).dmg"

hdiutil create -volname "Claude Talk" \
  -srcfolder "$APP_PATH" \
  -ov -format UDZO \
  "build/$DMG_NAME"

echo "DMG created: build/$DMG_NAME"
```

- [ ] **Step 4: Commit**

```bash
git add build.sh package-dmg.sh
git commit -m "feat: add build and DMG packaging scripts"
```

---

### Task 19: GitHub Actions CI for automated builds

**Files:**
- Create: `.github/workflows/build.yml`

- [ ] **Step 1: Create CI workflow**

```yaml
# .github/workflows/build.yml
name: Build

on:
  push:
    tags: ['v*']
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Build
        run: |
          cd ClaudeTalk
          xcodebuild -project ClaudeTalk.xcodeproj \
            -scheme ClaudeTalk \
            -configuration Release \
            -derivedDataPath build \
            build

      - name: Package DMG
        if: startsWith(github.ref, 'refs/tags/')
        run: |
          cd ClaudeTalk
          bash package-dmg.sh

      - name: Upload DMG
        if: startsWith(github.ref, 'refs/tags/')
        uses: softprops/action-gh-release@v1
        with:
          files: ClaudeTalk/build/*.dmg
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "feat: add GitHub Actions CI for build and release"
```

---

### Task 20: Update README for Swift version

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README**

Update the existing README to:
- Add download link for `.app` (GitHub Releases)
- Keep `pip install` section under "CLI Version (Legacy)"
- Add screenshots section (placeholder)
- Update feature list with Notch UI, customization options
- Add "How it works" section (simpler: just open the app)

- [ ] **Step 2: Move Python code to legacy branch**

```bash
git checkout -b legacy
git checkout main
# Python source stays accessible in legacy branch
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: update README for Swift app with download instructions"
```

---

## Summary

| Chunk | Tasks | What it delivers |
|-------|-------|-----------------|
| 1: Foundation | 1-5 | Xcode project, whisper.cpp, Settings, PostProcessor, TerminalDetector |
| 2: Audio & Transcription | 6-10 | AudioEngine, WhisperWrapper, ModelManager, InputSimulator, HotkeyManager |
| 3: Notch UI | 11-13 | NotchOverlay (slide animation + frosted glass), WaveformView, CharacterView |
| 4: Menu Bar & Orchestration | 14-16.5 | MenuBarController, RecordingOrchestrator, AppDelegate wiring, OnboardingWindow |
| 5: Polish & Distribution | 17-20 | App icon, build scripts, CI, README |

After Task 16.5, the app is fully functional. Tasks 17-20 are polish and distribution.

## Implementation Notes

- **Launch at Login**: Use `SMAppService.mainApp.register()` (macOS 13+) in Settings when `launchAtLogin` is toggled. Call `.unregister()` when turned off.
- **Terminals submenu**: Add a "Terminals" submenu in MenuBarController showing the default whitelist with checkmarks, plus an "Add Custom..." item that opens an `NSAlert` with a text field.
- **Pulsing animation**: In `showTranscribing()`, start a `Timer` at 0.1s interval that oscillates `waveformView.rms` between 0.1-0.3 to create the pulse effect. Invalidate when state changes.
- **Spec ambiguity**: Default hotkey resolved to **Fn** (per the Global Hotkey Capture section of the spec). The onboarding window allows changing it.
