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
        if let icon = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Claude Talk") {
            icon.isTemplate = true
            statusItem?.button?.image = icon
        }
        statusItem?.menu = buildMenu()
    }

    func showPermissionWarning() {
        statusItem?.button?.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Permission needed")
    }

    func clearPermissionWarning() {
        if let icon = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Claude Talk") {
            icon.isTemplate = true
            statusItem?.button?.image = icon
        }
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

        // Recording Mode
        menu.addItem(makeSubmenuItem(
            title: "Recording: \(settings.recordingMode == "hold" ? "Hold" : "Toggle")",
            submenu: buildRecordingModeMenu()
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

        // Translation
        let transDisplay = (settings.llmTargetLanguage != nil && !settings.llmTargetLanguage!.isEmpty) ? "→ \(settings.llmTargetLanguage!)" : "Off"
        menu.addItem(makeSubmenuItem(
            title: "Translation: \(transDisplay)",
            submenu: buildTranslationMenu()
        ))

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
        let options: [(value: String, label: String)] = [
            ("auto", "Auto (Follow Background)"),
            ("light", "Light Glass"),
            ("dark", "Dark Glass"),
        ]
        for option in options {
            let item = NSMenuItem(title: option.label, action: #selector(selectGlassStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.value
            item.state = settings.glassStyle == option.value ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func buildRecordingModeMenu() -> NSMenu {
        let menu = NSMenu()
        let options: [(value: String, label: String)] = [
            ("hold", "Hold to Record"),
            ("toggle", "Tap to Start / Tap to Stop"),
        ]
        for option in options {
            let item = NSMenuItem(title: option.label, action: #selector(selectRecordingMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.value
            item.state = settings.recordingMode == option.value ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func buildTranslationMenu() -> NSMenu {
        let menu = NSMenu()
        let currentLang = settings.llmTargetLanguage

        // Off
        let offItem = NSMenuItem(title: "Off (原语言输出)", action: #selector(selectTranslation(_:)), keyEquivalent: "")
        offItem.target = self
        offItem.representedObject = "" as String
        offItem.state = (currentLang == nil || currentLang!.isEmpty) ? .on : .off
        menu.addItem(offItem)

        menu.addItem(.separator())

        let langs: [(label: String, code: String)] = [
            ("English", "English"),
            ("繁體中文", "繁體中文"),
            ("简体中文", "简体中文"),
            ("日本語", "日本語"),
            ("한국어", "한국어"),
            ("Español", "Español"),
            ("Français", "Français"),
        ]
        for lang in langs {
            let item = NSMenuItem(title: lang.label, action: #selector(selectTranslation(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.code
            item.state = currentLang == lang.code ? .on : .off
            menu.addItem(item)
        }

        return menu
    }

    @objc private func selectTranslation(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        settings.llmTargetLanguage = value.isEmpty ? nil : value
        rebuildMenu()
    }

    @objc private func selectRecordingMode(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        settings.recordingMode = value
        rebuildMenu()
    }

    @objc private func selectGlassStyle(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        settings.glassStyle = value
        rebuildMenu()
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
