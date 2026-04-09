# LLM Polish: AI 整理 + 翻译

## 概述

在 Claude Talk 现有的语音转写 pipeline 后，加入可选的 LLM 后处理步骤，将碎片化的语音转写文字整理为有条理的内容，并可同时翻译为目标语言。

## Pipeline

```
录音 → faster-whisper（本地） → PostProcessor（去填充词 + 词典）
  → [fn+Option 触发] LLMService.polish()（整理 + 翻译，单次 API 调用）
  → 粘贴到终端
```

不按 Option 时，行为与现有完全一致。

## 1. 触发机制

### Hold 模式
- `fn` = 纯转写（现有行为）
- `fn + Option` = 转写 + LLM polish

### Toggle 模式
- 第一次按 `fn + Option` 开始录音时记住 modifier 状态
- 第二次按 `fn` 停止时，根据开始时的状态决定是否走 LLM

### 实作
- HotkeyManager 的 CGEvent tap callback 读取 `event.flags.contains(.maskAlternate)`
- delegate 方法改为 `hotkeyDidPress(withOption: Bool)`
- RecordingOrchestrator 用 `isLLMMode: Bool` 记住本次录音模式

## 2. LLM 服务层

### 新增文件：`ClaudeTalk/Processing/LLMService.swift`

### 职责
接收 raw text + 设定，调一次 API，返回整理/翻译后的文字。

### API 协议
支持两种格式，根据 provider 自动切换：
- **Anthropic native**：Messages API（`/v1/messages`），用于 Claude
- **OpenAI-compatible**：Chat Completions API（`/v1/chat/completions`），用于 OpenAI、Groq、DeepSeek、Ollama 等

### HTTP 实作
- 纯 Swift `URLSession`，不引入第三方依赖
- 异步调用，`DispatchQueue.global` + completion handler（与现有转写风格一致）

### Prompt

```
你是语音转文字的后处理助手。请对以下语音转写文本进行整理：
1. 修正不通顺的语句，使其更有条理
2. 保留原意，不要添加内容
3. 去除口语化的赘词和重复
4. 正确使用标点符号（逗号、句号、问号、冒号等）
5. 根据语意分段，每个段落聚焦一个主题
6. [如有目标语言] 整理后翻译为{targetLanguage}

直接输出整理后的文字，不要加任何说明或前缀。

原文：
{rawText}
```

## 3. Settings 新增

在 `Settings.swift` 新增以下属性（UserDefaults backed）：

| Key | 类型 | 默认值 | 说明 |
|-----|------|--------|------|
| `llmProvider` | String | `"anthropic"` | `"anthropic"` 或 `"openai-compatible"` |
| `llmApiKey` | String | `""` | API key |
| `llmModel` | String | `"claude-haiku-4-5-20251001"` | 模型 ID |
| `llmBaseURL` | String | `"https://api.anthropic.com"` | API base URL |
| `llmTargetLanguage` | String? | `nil` | 目标翻译语言，nil = 只整理不翻译 |

配置方式：`defaults write com.nelsonkuo.ClaudeTalk <key> <value>`

App UI 后续版本再加。

## 4. RecordingOrchestrator 改动

### 新增属性
- `isLLMMode: Bool`：录音开始时根据 Option 键状态设定
- `llmService: LLMService`：LLM 服务实例

### 流程变更
`stopAndTranscribe()` 转写完成后：
1. `isLLMMode == false` → PostProcessor → 粘贴（现有路径）
2. `isLLMMode == true` → PostProcessor → LLMService.polish() → 粘贴

### 错误处理
- 无 API key → 跳过 LLM，用转写结果
- 网络/API 错误 → fallback 到转写结果，UI 显示 warning 状态

## 5. UI 状态

NotchOverlay / RecordingPillModel 新增状态：

| 状态 | 触发时机 | 视觉 |
|------|----------|------|
| `polishing` | LLM 请求中 | 蓝色/紫色指示，区分于 transcribing |

现有状态不变：`idle → recording → transcribing → success/error/discarded`

LLM 模式：`idle → recording → transcribing → polishing → success/error`

## 6. 文件变更清单

| 文件 | 变更 |
|------|------|
| `Processing/LLMService.swift` | **新增** — LLM API 调用 |
| `Settings/Settings.swift` | 新增 5 个 LLM 属性 |
| `Input/HotkeyManager.swift` | delegate 方法加 `withOption` 参数，CGEvent 读 modifier |
| `Orchestrator/RecordingOrchestrator.swift` | 新增 `isLLMMode`，pipeline 分支 |
| `UI/RecordingPillModel.swift` | 新增 `.polishing` 状态 |
| `UI/RecordingPillView.swift` | polishing 状态的视觉表现 |
| `UI/NotchOverlay.swift` | 透传 polishing 状态 |

## 7. 不做的事

- 不做 App Settings UI（后续版本）
- 不做智能判断是否需要整理（用户通过 modifier 键自行决定）
- 不做本地 LLM（中文品质不够）
- 不在 Python 端加 LLM 逻辑（Swift 端直接 HTTP）
- 不做 streaming（整理文本通常短，一次返回即可）
