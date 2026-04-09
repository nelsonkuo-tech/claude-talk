# LLM Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional LLM post-processing to Claude Talk that reorganizes fragmented speech into clear text and optionally translates, triggered by fn+Option.

**Architecture:** Existing pipeline (faster-whisper → PostProcessor) unchanged. New `LLMService` sits after PostProcessor, activated only when user holds Option during hotkey press. Single LLM API call handles both text refinement and translation. Supports Anthropic native API and OpenAI-compatible API via provider config.

**Tech Stack:** Swift, URLSession (no new dependencies), Anthropic Messages API / OpenAI Chat Completions API

**Spec:** `docs/superpowers/specs/2026-04-09-llm-polish-design.md`

**Project root:** `/Users/nelson/Desktop/Artificial Intelligent/claude-talk/`
**Swift source root:** `ClaudeTalk/ClaudeTalk/`

---

### Task 1: Add LLM Settings

**Files:**
- Modify: `ClaudeTalk/ClaudeTalk/Settings/Settings.swift`

- [ ] **Step 1: Add LLM settings properties**

Add these properties after the existing `glassStyle` property (after line 104):

```swift
// MARK: - LLM Polish

var llmProvider: String {
    get { defaults.string(forKey: "llmProvider") ?? "anthropic" }
    set { defaults.set(newValue, forKey: "llmProvider") }
}

var llmApiKey: String {
    get { defaults.string(forKey: "llmApiKey") ?? "" }
    set { defaults.set(newValue, forKey: "llmApiKey") }
}

var llmModel: String {
    get { defaults.string(forKey: "llmModel") ?? "claude-haiku-4-5-20251001" }
    set { defaults.set(newValue, forKey: "llmModel") }
}

var llmBaseURL: String {
    get { defaults.string(forKey: "llmBaseURL") ?? "https://api.anthropic.com" }
    set { defaults.set(newValue, forKey: "llmBaseURL") }
}

var llmTargetLanguage: String? {
    get { defaults.string(forKey: "llmTargetLanguage") }
    set { defaults.set(newValue, forKey: "llmTargetLanguage") }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd ClaudeTalk && xcodebuild -scheme ClaudeTalk -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/Settings/Settings.swift
git commit -m "feat: add LLM polish settings (provider, apiKey, model, baseURL, targetLanguage)"
```

---

### Task 2: Create LLMService

**Files:**
- Create: `ClaudeTalk/ClaudeTalk/Processing/LLMService.swift`

- [ ] **Step 1: Create LLMService.swift**

```swift
import Foundation

class LLMService {
    private let settings = Settings.shared

    /// Polish raw transcription text using LLM.
    /// Calls completion on the calling queue (background).
    func polish(_ text: String, completion: @escaping (Result<String, Error>) -> Void) {
        let apiKey = settings.llmApiKey
        guard !apiKey.isEmpty else {
            completion(.failure(LLMError.noApiKey))
            return
        }

        let prompt = buildPrompt(text)
        let provider = settings.llmProvider

        if provider == "anthropic" {
            callAnthropic(prompt: prompt, apiKey: apiKey, completion: completion)
        } else {
            callOpenAICompatible(prompt: prompt, apiKey: apiKey, completion: completion)
        }
    }

    // MARK: - Prompt

    private func buildPrompt(_ text: String) -> String {
        let targetLang = settings.llmTargetLanguage
        let langLine: String
        if let lang = targetLang, !lang.isEmpty {
            langLine = "\n6. 整理后翻译为\(lang)"
        } else {
            langLine = ""
        }

        return """
        你是语音转文字的后处理助手。请对以下语音转写文本进行整理：
        1. 修正不通顺的语句，使其更有条理
        2. 保留原意，不要添加内容
        3. 去除口语化的赘词和重复
        4. 正确使用标点符号（逗号、句号、问号、冒号等）
        5. 根据语意分段，每个段落聚焦一个主题\(langLine)

        直接输出整理后的文字，不要加任何说明或前缀。

        原文：
        \(text)
        """
    }

    // MARK: - Anthropic Messages API

    private func callAnthropic(prompt: String, apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        let baseURL = settings.llmBaseURL
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            completion(.failure(LLMError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": settings.llmModel,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(LLMError.serializationFailed))
            return
        }
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("[ClaudeTalk] LLM request failed: %@", error.localizedDescription)
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(LLMError.noData))
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let content = json["content"] as? [[String: Any]],
                      let first = content.first,
                      let text = first["text"] as? String else {
                    NSLog("[ClaudeTalk] LLM unexpected response: %@", String(data: data, encoding: .utf8) ?? "nil")
                    completion(.failure(LLMError.unexpectedResponse))
                    return
                }
                completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - OpenAI-Compatible Chat Completions API

    private func callOpenAICompatible(prompt: String, apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        let baseURL = settings.llmBaseURL
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            completion(.failure(LLMError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": settings.llmModel,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(LLMError.serializationFailed))
            return
        }
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("[ClaudeTalk] LLM request failed: %@", error.localizedDescription)
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(LLMError.noData))
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let first = choices.first,
                      let message = first["message"] as? [String: Any],
                      let text = message["content"] as? String else {
                    NSLog("[ClaudeTalk] LLM unexpected response: %@", String(data: data, encoding: .utf8) ?? "nil")
                    completion(.failure(LLMError.unexpectedResponse))
                    return
                }
                completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case noApiKey
    case invalidURL
    case serializationFailed
    case noData
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .noApiKey: return "No LLM API key configured"
        case .invalidURL: return "Invalid LLM base URL"
        case .serializationFailed: return "Failed to serialize request"
        case .noData: return "No data in LLM response"
        case .unexpectedResponse: return "Unexpected LLM response format"
        }
    }
}
```

- [ ] **Step 2: Add file to Xcode project**

If using `project.yml` (XcodeGen), the file should be auto-discovered under `ClaudeTalk/ClaudeTalk/`. Regenerate if needed:

```bash
cd ClaudeTalk && xcodegen generate 2>&1
```

- [ ] **Step 3: Build to verify**

Run: `cd ClaudeTalk && xcodebuild -scheme ClaudeTalk -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/Processing/LLMService.swift
git commit -m "feat: add LLMService with Anthropic and OpenAI-compatible API support"
```

---

### Task 3: Add polishing UI state

**Files:**
- Modify: `ClaudeTalk/ClaudeTalk/UI/RecordingPillModel.swift`
- Modify: `ClaudeTalk/ClaudeTalk/UI/RecordingPillView.swift`
- Modify: `ClaudeTalk/ClaudeTalk/UI/NotchOverlay.swift`

- [ ] **Step 1: Add `polishing` case to RecordingUIState**

In `RecordingPillModel.swift` line 3, change:

```swift
enum RecordingUIState {
    case idle, recording, transcribing, done, error
}
```

to:

```swift
enum RecordingUIState {
    case idle, recording, transcribing, polishing, done, error
}
```

- [ ] **Step 2: Add polishing transition in RecordingPillModel**

In `RecordingPillModel.swift`, inside `transitionTo(_:)`, add a new case after the `.transcribing` case (after line 47):

```swift
        case .polishing:
            state = .polishing
            startPulse()
```

- [ ] **Step 3: Update RecordingPillView to show polishing state**

In `RecordingPillView.swift` line 15, change:

```swift
        let isActive = model.state == .recording || model.state == .transcribing
```

to:

```swift
        let isActive = model.state == .recording || model.state == .transcribing || model.state == .polishing
```

In `RecordingPillView.swift`, update `iconImage` (lines 48-66). Replace the entire `@ViewBuilder private var iconImage` computed property:

```swift
    @ViewBuilder
    private var iconImage: some View {
        switch model.state {
        case .idle:
            Image(systemName: "mic.fill")
                .foregroundStyle(.white)
        case .recording, .transcribing:
            Image(systemName: "mic.fill")
                .foregroundStyle(activeGreen)
                .symbolEffect(.pulse, isActive: model.state == .transcribing)
        case .polishing:
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .symbolEffect(.pulse, isActive: true)
        case .done:
            Image(systemName: "checkmark")
                .foregroundStyle(activeGreen)
                .fontWeight(.bold)
        case .error:
            Image(systemName: "xmark")
                .foregroundStyle(.red)
                .fontWeight(.bold)
        }
    }
```

- [ ] **Step 4: Add polishing state to NotchOverlay**

In `NotchOverlay.swift` line 135, change:

```swift
enum NotchState: Int {
    case idle = 0, recording = 1, transcribing = 2, success = 3, error = 4, discarded = 5
}
```

to:

```swift
enum NotchState: Int {
    case idle = 0, recording = 1, transcribing = 2, polishing = 3, success = 4, error = 5, discarded = 6
}
```

In `NotchOverlay.swift`, inside `handleStateChange(from:to:)`, add a new case after `.transcribing` (after line 77):

```swift
        case .polishing:
            model.transitionTo(.polishing)
```

- [ ] **Step 5: Build to verify**

Run: `cd ClaudeTalk && xcodebuild -scheme ClaudeTalk -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/UI/RecordingPillModel.swift ClaudeTalk/ClaudeTalk/UI/RecordingPillView.swift ClaudeTalk/ClaudeTalk/UI/NotchOverlay.swift
git commit -m "feat: add polishing UI state with sparkles icon and purple accent"
```

---

### Task 4: Pass Option modifier through HotkeyManager

**Files:**
- Modify: `ClaudeTalk/ClaudeTalk/Input/HotkeyManager.swift`

- [ ] **Step 1: Update delegate protocol**

In `HotkeyManager.swift`, replace the protocol (lines 4-7):

```swift
protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyDidPress()
    func hotkeyDidRelease()
}
```

with:

```swift
protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyDidPress(withOption: Bool)
    func hotkeyDidRelease()
}
```

- [ ] **Step 2: Pass Option flag in handleEvent**

In `HotkeyManager.swift`, update the three `delegate?.hotkeyDidPress()` call sites.

Replace line 107 (inside `flagsChanged` case):

```swift
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyDidPress()
                }
```

with:

```swift
                let hasOption = event.flags.contains(.maskAlternate)
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyDidPress(withOption: hasOption)
                }
```

Replace lines 119-121 (inside `keyDown` case):

```swift
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.hotkeyDidPress()
            }
```

with:

```swift
            let hasOption = event.flags.contains(.maskAlternate)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.hotkeyDidPress(withOption: hasOption)
            }
```

- [ ] **Step 3: Build to verify**

This will fail because RecordingOrchestrator still conforms to old protocol. That's expected — we fix it in Task 5.

- [ ] **Step 4: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/Input/HotkeyManager.swift
git commit -m "feat: pass Option modifier flag through HotkeyManager delegate"
```

---

### Task 5: Wire LLM polish into RecordingOrchestrator

**Files:**
- Modify: `ClaudeTalk/ClaudeTalk/Orchestrator/RecordingOrchestrator.swift`

- [ ] **Step 1: Add LLM properties**

After `private var isToggleRecording = false` (line 16), add:

```swift
    private var isLLMMode = false
    private let llmService = LLMService()
```

- [ ] **Step 2: Update hotkeyDidPress to accept withOption**

Replace the entire `hotkeyDidPress()` method (lines 63-108) with:

```swift
    func hotkeyDidPress(withOption: Bool) {
        NSLog("[ClaudeTalk] Hotkey pressed! option=%@", withOption ? "YES" : "NO")

        if settings.recordingMode == "toggle" {
            if isToggleRecording {
                isToggleRecording = false
                stopAndTranscribe()
                return
            }

            guard !isTranscribing else { NSLog("[ClaudeTalk] Skipped: still transcribing"); return }
            let focused = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
            NSLog("[ClaudeTalk] Focused app: %@", focused)
            guard terminalDetector.isFocusedAppTerminal() else { NSLog("[ClaudeTalk] Skipped: %@ not in terminal whitelist", focused); return }

            do {
                try audioEngine.startRecording()
                isToggleRecording = true
                isLLMMode = withOption
            } catch {
                NSLog("[ClaudeTalk] Recording failed: %@", error.localizedDescription)
                notchOverlay.state = .error
                return
            }
            notchOverlay.state = .recording
            return
        }

        // Hold mode
        guard !isTranscribing else { NSLog("[ClaudeTalk] Skipped: still transcribing"); return }
        let focused = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        NSLog("[ClaudeTalk] Focused app: %@", focused)
        guard terminalDetector.isFocusedAppTerminal() else { NSLog("[ClaudeTalk] Skipped: %@ not in terminal whitelist", focused); return }

        do {
            try audioEngine.startRecording()
            isLLMMode = withOption
        } catch {
            NSLog("[ClaudeTalk] Recording failed: %@", error.localizedDescription)
            notchOverlay.state = .error
            return
        }

        notchOverlay.state = .recording
    }
```

- [ ] **Step 3: Update finishTranscription to support LLM polish**

Replace the existing `finishTranscription(_:)` method (lines 229-242) with:

```swift
    private func finishTranscription(_ text: String) {
        guard !text.isEmpty else {
            notchOverlay.state = .error
            return
        }

        if isLLMMode && !settings.llmApiKey.isEmpty {
            notchOverlay.state = .polishing
            llmService.polish(text) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    let finalText: String
                    switch result {
                    case .success(let polished):
                        NSLog("[ClaudeTalk] LLM polish succeeded (%d → %d chars)", text.count, polished.count)
                        finalText = polished
                    case .failure(let error):
                        NSLog("[ClaudeTalk] LLM polish failed: %@, using raw text", error.localizedDescription)
                        finalText = text
                    }
                    self.pasteResult(finalText)
                }
            }
        } else {
            pasteResult(text)
        }
    }

    private func pasteResult(_ text: String) {
        guard terminalDetector.isFocusedAppTerminal() else {
            notchOverlay.state = .error
            return
        }

        InputSimulator.paste(text)
        notchOverlay.state = .success
    }
```

- [ ] **Step 4: Build to verify**

Run: `cd ClaudeTalk && xcodebuild -scheme ClaudeTalk -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ClaudeTalk/ClaudeTalk/Orchestrator/RecordingOrchestrator.swift
git commit -m "feat: wire LLM polish into recording pipeline with Option key trigger"
```

---

### Task 6: Manual smoke test

- [ ] **Step 1: Configure API key**

```bash
defaults write com.claude-talk.ClaudeTalk llmApiKey "sk-ant-YOUR-KEY-HERE"
```

- [ ] **Step 2: Build and run**

```bash
cd ClaudeTalk && xcodebuild -scheme ClaudeTalk -configuration Debug build 2>&1 | tail -5
open build/Build/Products/Debug/ClaudeTalk.app
```

- [ ] **Step 3: Test normal mode (fn only)**

Hold `fn`, speak a short sentence, release. Verify text is pasted as before — no LLM call.

- [ ] **Step 4: Test LLM mode (fn + Option)**

Hold `fn + Option`, speak a fragmented sentence (e.g., "就是那个...我觉得...嗯...这个功能应该要可以...让用户...就是可以搜索"), release. Verify:
- UI shows `transcribing` → `polishing` (sparkles icon, purple)
- Output text is reorganized and punctuated
- Latency is acceptable (< 2s total for LLM step)

- [ ] **Step 5: Test translation**

```bash
defaults write com.claude-talk.ClaudeTalk llmTargetLanguage "English"
```

Hold `fn + Option`, speak in Chinese, verify output is in English.

- [ ] **Step 6: Test fallback (no API key)**

```bash
defaults delete com.claude-talk.ClaudeTalk llmApiKey
```

Hold `fn + Option`, speak, verify it falls back to raw transcription (no crash, no hang).

- [ ] **Step 7: Commit final state**

```bash
git add -A
git commit -m "feat: LLM polish complete — AI text refinement and translation via fn+Option"
```
