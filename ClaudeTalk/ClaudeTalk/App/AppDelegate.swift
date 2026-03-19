import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, MenuBarDelegate, OnboardingDelegate {
    private let menuBar = MenuBarController()
    private let orchestrator = RecordingOrchestrator()
    private let modelManager = ModelManager()
    private var onboarding: OnboardingWindow?
    private var accessibilityTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Check accessibility — open System Settings if not trusted
        if !AXIsProcessTrusted() {
            promptAccessibility()
        }

        // 2. Setup menu bar
        menuBar.setup()
        menuBar.delegate = self

        // 3. Check model and start
        let model = Settings.shared.modelSize
        if modelManager.isDownloaded(model) {
            orchestrator.start()
        } else {
            let window = OnboardingWindow()
            window.onboardingDelegate = self
            onboarding = window
            window.startSetup()
        }

        // 4. Monitor accessibility until granted
        startAccessibilityMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessibilityTimer?.invalidate()
        orchestrator.stop()
    }

    // MARK: - Accessibility

    private func promptAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }

    private func startAccessibilityMonitor() {
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            let trusted = AXIsProcessTrusted()
            if trusted {
                self?.menuBar.clearPermissionWarning()
                timer.invalidate()
                self?.accessibilityTimer = nil
                NSLog("[ClaudeTalk] Accessibility granted")
            } else {
                self?.menuBar.showPermissionWarning()
            }
        }
    }

    // MARK: - MenuBarDelegate

    func menuBarDidChangeSettings() {
        orchestrator.reloadSettings()
    }

    // MARK: - OnboardingDelegate

    func onboardingDidComplete() {
        onboarding = nil
        orchestrator.start()
    }
}
