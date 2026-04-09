import Foundation

final class Settings {
    static var shared = Settings(defaults: .standard)

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: - Keys

    private enum Key {
        static let hotkey = "hotkey"
        static let modelSize = "modelSize"
        static let language = "language"
        static let terminalWhitelist = "terminalWhitelist"
        static let launchAtLogin = "launchAtLogin"
        static let removeFillerWords = "removeFillerWords"
        static let accentColor = "accentColor"
        static let waveformStyle = "waveformStyle"
        static let pillStyle = "pillStyle"
        static let promptHint = "promptHint"
    }

    // MARK: - Properties

    var hotkey: String {
        get { defaults.string(forKey: Key.hotkey) ?? "fn" }
        set { defaults.set(newValue, forKey: Key.hotkey) }
    }

    var modelSize: String {
        get { defaults.string(forKey: Key.modelSize) ?? "small" }
        set { defaults.set(newValue, forKey: Key.modelSize) }
    }

    var language: String? {
        get {
            if defaults.object(forKey: Key.language) == nil {
                return "zh"
            }
            return defaults.string(forKey: Key.language)
        }
        set { defaults.set(newValue, forKey: Key.language) }
    }

    var terminalWhitelist: [String] {
        get {
            if let stored = defaults.array(forKey: Key.terminalWhitelist) as? [String] {
                return stored
            }
            return ["terminal", "iterm2", "ghostty", "kitty", "warp", "alacritty", "wezterm", "hyper"]
        }
        set { defaults.set(newValue, forKey: Key.terminalWhitelist) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    var removeFillerWords: Bool {
        get {
            if defaults.object(forKey: Key.removeFillerWords) == nil {
                return true
            }
            return defaults.bool(forKey: Key.removeFillerWords)
        }
        set { defaults.set(newValue, forKey: Key.removeFillerWords) }
    }

    var accentColor: String {
        get { defaults.string(forKey: Key.accentColor) ?? "white" }
        set { defaults.set(newValue, forKey: Key.accentColor) }
    }

    var waveformStyle: String {
        get { defaults.string(forKey: Key.waveformStyle) ?? "bars" }
        set { defaults.set(newValue, forKey: Key.waveformStyle) }
    }

    var pillStyle: String {
        get { defaults.string(forKey: Key.pillStyle) ?? "solid" }
        set { defaults.set(newValue, forKey: Key.pillStyle) }
    }

    var promptHint: String {
        get { defaults.string(forKey: Key.promptHint) ?? "以下是中英文夹杂的内容。Contains both Chinese and English." }
        set { defaults.set(newValue, forKey: Key.promptHint) }
    }

    // Recording mode: "hold" (hold to record) or "toggle" (tap to start/stop)
    var recordingMode: String {
        get { defaults.string(forKey: "recordingMode") ?? "hold" }
        set { defaults.set(newValue, forKey: "recordingMode") }
    }

    // Glass style: "auto", "light", "dark"
    var glassStyle: String {
        get { defaults.string(forKey: "glassStyle") ?? "auto" }
        set { defaults.set(newValue, forKey: "glassStyle") }
    }

    // Allow voice input in all apps, not just terminals
    var allowAllApps: Bool {
        get {
            if defaults.object(forKey: "allowAllApps") == nil {
                return true  // default: enabled
            }
            return defaults.bool(forKey: "allowAllApps")
        }
        set { defaults.set(newValue, forKey: "allowAllApps") }
    }

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
}
