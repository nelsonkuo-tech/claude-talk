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
