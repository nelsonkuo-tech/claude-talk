import AppKit
import ServiceManagement

protocol MenuBarDelegate: AnyObject {
    func menuBarDidChangeSettings()
}

class MenuBarController {
    weak var delegate: MenuBarDelegate?
    private var statusItem: NSStatusItem?
    private let settings = Settings.shared

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Claude Talk")
        statusItem?.menu = buildMenu()
    }

    func showPermissionWarning() {
        statusItem?.button?.image = NSImage(systemSymbolName: "mic.badge.xmark", accessibilityDescription: "Permission needed")
    }

    func clearPermissionWarning() {
        statusItem?.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Claude Talk")
    }

    // MARK: - Menu Building

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Header
        let header = NSMenuItem(title: "Claude Talk", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let statusLabel = NSMenuItem(title: "Running", action: nil, keyEquivalent: "")
        statusLabel.isEnabled = false
        menu.addItem(statusLabel)

        menu.addItem(.separator())

        // Hotkey
        menu.addItem(makeSubmenuItem(
            title: "Hotkey: \(settings.hotkey)",
            submenu: buildHotkeyMenu()
        ))

        // Model
        menu.addItem(makeSubmenuItem(
            title: "Model: \(settings.modelSize)",
            submenu: buildModelMenu()
        ))

        // Language
        let langDisplay = languageDisplayName(settings.language)
        menu.addItem(makeSubmenuItem(
            title: "Language: \(langDisplay)",
            submenu: buildLanguageMenu()
        ))

        // Terminals
        menu.addItem(makeSubmenuItem(
            title: "Terminals: Auto",
            submenu: buildTerminalsMenu()
        ))

        menu.addItem(.separator())

        // Appearance submenu
        menu.addItem(makeSubmenuItem(
            title: "Appearance",
            submenu: buildAppearanceMenu()
        ))

        menu.addItem(.separator())

        // Launch at Login
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = settings.launchAtLogin ? .on : .off
        menu.addItem(launchItem)

        // Remove Filler Words
        let fillerItem = NSMenuItem(title: "Remove Filler Words", action: #selector(toggleRemoveFillerWords), keyEquivalent: "")
        fillerItem.target = self
        fillerItem.state = settings.removeFillerWords ? .on : .off
        menu.addItem(fillerItem)

        // Edit Dictionary
        let dictItem = NSMenuItem(title: "Edit Dictionary...", action: #selector(editDictionary), keyEquivalent: "")
        dictItem.target = self
        menu.addItem(dictItem)

        menu.addItem(.separator())

        // About
        let aboutItem = NSMenuItem(title: "About Claude Talk", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func makeSubmenuItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    // MARK: - Submenus

    private func buildHotkeyMenu() -> NSMenu {
        let menu = NSMenu()
        let options = ["fn", "left_option", "right_option", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12"]
        for option in options {
            let item = NSMenuItem(title: option, action: #selector(selectHotkey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option
            item.state = settings.hotkey == option ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func buildModelMenu() -> NSMenu {
        let menu = NSMenu()
        let options = ["tiny", "base", "small", "medium"]
        for option in options {
            let item = NSMenuItem(title: option, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option
            item.state = settings.modelSize == option ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func buildLanguageMenu() -> NSMenu {
        let menu = NSMenu()
        let options: [(label: String, code: String?)] = [
            ("Auto", nil),
            ("English (en)", "en"),
            ("中文 (zh)", "zh"),
            ("日本語 (ja)", "ja"),
            ("한국어 (ko)", "ko"),
            ("Español (es)", "es")
        ]
        for option in options {
            let item = NSMenuItem(title: option.label, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.code
            item.state = settings.language == option.code ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func buildTerminalsMenu() -> NSMenu {
        let menu = NSMenu()
        let allTerminals = ["terminal", "iterm2", "ghostty", "kitty", "warp", "alacritty", "wezterm", "hyper"]
        let whitelist = settings.terminalWhitelist
        for terminal in allTerminals {
            let item = NSMenuItem(title: terminal, action: #selector(toggleTerminal(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = terminal
            item.state = whitelist.contains(terminal) ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func buildAppearanceMenu() -> NSMenu {
        let menu = NSMenu()

        // Accent Color
        menu.addItem(makeSubmenuItem(title: "Accent Color", submenu: buildAccentColorMenu()))

        // Waveform Style
        menu.addItem(makeSubmenuItem(title: "Waveform Style", submenu: buildWaveformStyleMenu()))

        // Pill Style
        menu.addItem(makeSubmenuItem(title: "Pill Style", submenu: buildPillStyleMenu()))

        return menu
    }

    private func buildAccentColorMenu() -> NSMenu {
        let menu = NSMenu()
        let options = ["white", "purple", "cyan", "green", "orange", "pink"]
        let labels = ["White", "Purple", "Cyan", "Green", "Orange", "Pink"]
        for (option, label) in zip(options, labels) {
            let item = NSMenuItem(title: label, action: #selector(selectAccentColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option
            item.state = settings.accentColor == option ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func buildWaveformStyleMenu() -> NSMenu {
        let menu = NSMenu()
        let options = ["bars", "dots", "line", "cat", "rabbit", "dog"]
        let labels = ["Bars", "Dots", "Line", "🐱 Cat", "🐰 Rabbit", "🐶 Dog"]
        for (option, label) in zip(options, labels) {
            let item = NSMenuItem(title: label, action: #selector(selectWaveformStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option
            item.state = settings.waveformStyle == option ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func buildPillStyleMenu() -> NSMenu {
        let menu = NSMenu()
        let options = [("solid", "Solid Black"), ("frosted", "Frosted Glass")]
        for (option, label) in options {
            let item = NSMenuItem(title: label, action: #selector(selectPillStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option
            item.state = settings.pillStyle == option ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    // MARK: - Helpers

    private func languageDisplayName(_ code: String?) -> String {
        guard let code = code else { return "Auto" }
        switch code {
        case "en": return "English (en)"
        case "zh": return "中文 (zh)"
        case "ja": return "日本語 (ja)"
        case "ko": return "한국어 (ko)"
        case "es": return "Español (es)"
        default: return code
        }
    }

    private func rebuildMenu() {
        statusItem?.menu = buildMenu()
        delegate?.menuBarDidChangeSettings()
    }

    // MARK: - Actions

    @objc private func selectHotkey(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        settings.hotkey = value
        rebuildMenu()
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        settings.modelSize = value
        rebuildMenu()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        settings.language = sender.representedObject as? String
        rebuildMenu()
    }

    @objc private func toggleTerminal(_ sender: NSMenuItem) {
        guard let terminal = sender.representedObject as? String else { return }
        var whitelist = settings.terminalWhitelist
        if whitelist.contains(terminal) {
            whitelist.removeAll { $0 == terminal }
        } else {
            whitelist.append(terminal)
        }
        settings.terminalWhitelist = whitelist
        rebuildMenu()
    }

    @objc private func selectAccentColor(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        settings.accentColor = value
        rebuildMenu()
    }

    @objc private func selectWaveformStyle(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        settings.waveformStyle = value
        rebuildMenu()
    }

    @objc private func selectPillStyle(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        settings.pillStyle = value
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        settings.launchAtLogin.toggle()
        if settings.launchAtLogin {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
        rebuildMenu()
    }

    @objc private func toggleRemoveFillerWords() {
        settings.removeFillerWords.toggle()
        rebuildMenu()
    }

    @objc private func editDictionary() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dictURL = appSupport.appendingPathComponent("Claude Talk/dictionary.json")
        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: dictURL.path) {
            let dir = dictURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? "[]".write(to: dictURL, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(dictURL)
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
