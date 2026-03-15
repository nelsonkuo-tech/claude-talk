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
        get { defaults.string(forKey: Key.modelSize) ?? "base" }
        set { defaults.set(newValue, forKey: Key.modelSize) }
    }

    var language: String? {
        get { defaults.string(forKey: Key.language) }
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
}
