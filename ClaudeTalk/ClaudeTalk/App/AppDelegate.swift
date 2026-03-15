import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, MenuBarDelegate, OnboardingDelegate {
    private let menuBar = MenuBarController()
    private let orchestrator = RecordingOrchestrator()
    private let modelManager = ModelManager()
    private var onboarding: OnboardingWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Check accessibility permission
        if !AXIsProcessTrusted() {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
            AXIsProcessTrustedWithOptions(options)
        }

        // 2. Setup menu bar
        menuBar.setup()
        menuBar.delegate = self

        if !AXIsProcessTrusted() {
            menuBar.showPermissionWarning()
        }

        // 3. Check model and start or show onboarding
        let model = Settings.shared.modelSize
        if modelManager.isDownloaded(model) {
            orchestrator.start()
        } else {
            let window = OnboardingWindow()
            window.onboardingDelegate = self
            onboarding = window
            window.startSetup()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        orchestrator.stop()
    }

    // MARK: - MenuBarDelegate

    func menuBarDidChangeSettings() {
        orchestrator.reloadSettings()
    }

    // MARK: - OnboardingDelegate

    func onboardingDidComplete() {
        onboarding = nil
        if AXIsProcessTrusted() {
            menuBar.clearPermissionWarning()
        }
        orchestrator.start()
    }
}
