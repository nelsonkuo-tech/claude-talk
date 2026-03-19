import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, MenuBarDelegate, OnboardingDelegate {
    private let menuBar = MenuBarController()
    private let orchestrator = RecordingOrchestrator()
    private let modelManager = ModelManager()
    private var onboarding: OnboardingWindow?
    private var accessibilityTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Prompt accessibility if not trusted (non-blocking)
        if !AXIsProcessTrusted() {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
            AXIsProcessTrustedWithOptions(options)
        }

        // 2. Setup menu bar — always show normal icon first
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

        // 4. Periodically check accessibility and update icon
        startAccessibilityMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessibilityTimer?.invalidate()
        orchestrator.stop()
    }

    // MARK: - Accessibility Monitor

    private func startAccessibilityMonitor() {
        // Check every 2 seconds until trusted, then stop
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            let trusted = AXIsProcessTrusted()
            NSLog("[ClaudeTalk] Accessibility check: %@", trusted ? "YES" : "NO")
            if trusted {
                self?.menuBar.clearPermissionWarning()
                timer.invalidate()
                self?.accessibilityTimer = nil
            }
            // Don't show warning icon — unreliable during development
            // due to code signature changes on each rebuild
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
