import XCTest
@testable import ClaudeTalk

final class SettingsTests: XCTestCase {

    var suiteName: String!
    var defaults: UserDefaults!
    var settings: Settings!

    override func setUp() {
        super.setUp()
        suiteName = "com.claude-talk.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        settings = Settings(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Default Values

    func testDefaultHotkey() {
        XCTAssertEqual(settings.hotkey, "fn")
    }

    func testDefaultModelSize() {
        XCTAssertEqual(settings.modelSize, "base")
    }

    func testDefaultLanguageIsNil() {
        XCTAssertNil(settings.language)
    }

    func testDefaultTerminalWhitelist() {
        let expected = ["terminal", "iterm2", "ghostty", "kitty", "warp", "alacritty", "wezterm", "hyper"]
        XCTAssertEqual(settings.terminalWhitelist, expected)
    }

    func testDefaultLaunchAtLogin() {
        XCTAssertFalse(settings.launchAtLogin)
    }

    func testDefaultRemoveFillerWords() {
        XCTAssertTrue(settings.removeFillerWords)
    }

    func testDefaultAccentColor() {
        XCTAssertEqual(settings.accentColor, "white")
    }

    func testDefaultWaveformStyle() {
        XCTAssertEqual(settings.waveformStyle, "bars")
    }

    func testDefaultPillStyle() {
        XCTAssertEqual(settings.pillStyle, "solid")
    }

    func testDefaultPromptHint() {
        XCTAssertEqual(settings.promptHint, "以下是中英文夹杂的内容。Contains both Chinese and English.")
    }

    // MARK: - Persistence

    func testHotkeyPersists() {
        settings.hotkey = "ctrl"
        let settings2 = Settings(defaults: defaults)
        XCTAssertEqual(settings2.hotkey, "ctrl")
    }

    func testModelSizePersists() {
        settings.modelSize = "large"
        let settings2 = Settings(defaults: defaults)
        XCTAssertEqual(settings2.modelSize, "large")
    }

    func testLanguagePersists() {
        settings.language = "zh"
        let settings2 = Settings(defaults: defaults)
        XCTAssertEqual(settings2.language, "zh")
    }

    func testLanguageCanBeSetToNil() {
        settings.language = "en"
        settings.language = nil
        let settings2 = Settings(defaults: defaults)
        XCTAssertNil(settings2.language)
    }

    func testTerminalWhitelistPersists() {
        settings.terminalWhitelist = ["terminal", "iterm2"]
        let settings2 = Settings(defaults: defaults)
        XCTAssertEqual(settings2.terminalWhitelist, ["terminal", "iterm2"])
    }

    func testLaunchAtLoginPersists() {
        settings.launchAtLogin = true
        let settings2 = Settings(defaults: defaults)
        XCTAssertTrue(settings2.launchAtLogin)
    }

    func testRemoveFillerWordsPersistsWhenSetToFalse() {
        settings.removeFillerWords = false
        let settings2 = Settings(defaults: defaults)
        XCTAssertFalse(settings2.removeFillerWords)
    }

    func testRemoveFillerWordsPersistsWhenSetToTrue() {
        settings.removeFillerWords = true
        let settings2 = Settings(defaults: defaults)
        XCTAssertTrue(settings2.removeFillerWords)
    }

    func testAccentColorPersists() {
        settings.accentColor = "blue"
        let settings2 = Settings(defaults: defaults)
        XCTAssertEqual(settings2.accentColor, "blue")
    }

    func testWaveformStylePersists() {
        settings.waveformStyle = "line"
        let settings2 = Settings(defaults: defaults)
        XCTAssertEqual(settings2.waveformStyle, "line")
    }

    func testPillStylePersists() {
        settings.pillStyle = "outline"
        let settings2 = Settings(defaults: defaults)
        XCTAssertEqual(settings2.pillStyle, "outline")
    }

    func testPromptHintPersists() {
        settings.promptHint = "Custom hint"
        let settings2 = Settings(defaults: defaults)
        XCTAssertEqual(settings2.promptHint, "Custom hint")
    }
}
