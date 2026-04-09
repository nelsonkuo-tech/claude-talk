import AppKit

struct TerminalDetector {
    static let defaultWhitelist = [
        "terminal", "iterm2", "ghostty", "kitty", "warp", "alacritty", "wezterm", "hyper"
    ]

    private let whitelist: Set<String>
    private let allowAllApps: Bool

    init(whitelist: [String]? = nil, allowAllApps: Bool = false) {
        self.whitelist = Set((whitelist ?? Self.defaultWhitelist).map { $0.lowercased() })
        self.allowAllApps = allowAllApps
    }

    func isTerminal(_ appName: String) -> Bool {
        whitelist.contains(appName.lowercased())
    }

    func isFocusedAppTerminal() -> Bool {
        if allowAllApps { return true }
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let name = app.localizedName ?? ""
        return isTerminal(name)
    }
}
