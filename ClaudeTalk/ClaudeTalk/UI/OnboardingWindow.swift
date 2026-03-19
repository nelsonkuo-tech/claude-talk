import AppKit

protocol OnboardingDelegate: AnyObject {
    func onboardingDidComplete()
}

class OnboardingWindow: NSWindowController {
    weak var onboardingDelegate: OnboardingDelegate?
    private let modelManager = ModelManager()
    private let settings = Settings.shared
    private var progressBar: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var continueButton: NSButton!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Talk Setup"
        window.center()
        self.init(window: window)
        setupUI()
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Title label
        let titleLabel = NSTextField(labelWithString: "Welcome to Claude Talk")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // Subtitle label
        let subtitleLabel = NSTextField(labelWithString: "Press-to-talk voice input for Claude Code")
        subtitleLabel.font = NSFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)

        // Status label
        statusLabel = NSTextField(labelWithString: "Preparing to download Whisper model...")
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)

        // Progress bar
        progressBar = NSProgressIndicator()
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressBar)

        // Continue button
        continueButton = NSButton(title: "Continue", target: self, action: #selector(didTapContinue))
        continueButton.bezelStyle = .rounded
        continueButton.isEnabled = false
        continueButton.keyEquivalent = "\r"
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(continueButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            statusLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 36),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            progressBar.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            progressBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            progressBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),

            continueButton.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 28),
            continueButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            continueButton.widthAnchor.constraint(equalToConstant: 120)
        ])
    }

    // MARK: - Public Entry Point

    func startSetup() {
        showWindow(nil)
        downloadModel()
    }

    // MARK: - Download

    private func downloadModel() {
        let model = settings.modelSize

        if modelManager.isDownloaded(model) {
            onDownloadComplete()
            return
        }

        statusLabel.stringValue = "Downloading Whisper \(model) model..."
        progressBar.doubleValue = 0

        modelManager.download(model, progress: { [weak self] fraction in
            DispatchQueue.main.async {
                self?.progressBar.doubleValue = fraction
                let pct = Int(fraction * 100)
                self?.statusLabel.stringValue = "Downloading Whisper \(model) model… \(pct)%"
            }
        }, completion: { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.onDownloadComplete()
                case .failure(let error):
                    self?.statusLabel.stringValue = "Download failed: \(error.localizedDescription)"
                    self?.progressBar.doubleValue = 0
                }
            }
        })
    }

    // MARK: - Post-download

    private func onDownloadComplete() {
        progressBar.doubleValue = 1
        statusLabel.stringValue = "Model ready. Grant Accessibility to enable typing."
        continueButton.isEnabled = true
        promptAccessibility()
    }

    private func promptAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Actions

    @objc private func didTapContinue() {
        close()
        onboardingDelegate?.onboardingDidComplete()
    }
}
