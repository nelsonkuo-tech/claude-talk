import AppKit

class NotchContentView: NSView {
    private let waveformView = WaveformView()
    private let timerLabel = NSTextField(labelWithString: "0:00")
    private var timer: Timer?
    private var recordingStartTime: Date?
    private var useCharacter = false
    // characterView will be added by Task 13; placeholder for now
    private let characterPlaceholder = NSView()

    // Pulse timer used during transcribing state
    private var pulseTimer: Timer?
    private var pulsePhase: Double = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSubviews()
    }

    // MARK: - Setup

    private func setupSubviews() {
        // Waveform
        waveformView.frame = NSRect(x: 16, y: 4, width: 80, height: 28)
        addSubview(waveformView)

        // Character placeholder (hidden by default)
        characterPlaceholder.frame = NSRect(x: 26, y: 4, width: 28, height: 28)
        characterPlaceholder.isHidden = true
        addSubview(characterPlaceholder)

        // Timer label
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        timerLabel.textColor = .white
        timerLabel.alignment = .right
        timerLabel.isBezeled = false
        timerLabel.isEditable = false
        timerLabel.drawsBackground = false
        addSubview(timerLabel)
    }

    override func layout() {
        super.layout()
        timerLabel.frame = NSRect(x: bounds.width - 60, y: 8, width: 50, height: 20)
    }

    // MARK: - Public API

    func configure(waveformStyle: String, accentColor: NSColor) {
        let characterStyles = ["cat", "rabbit", "dog"]
        useCharacter = characterStyles.contains(waveformStyle.lowercased())

        if useCharacter {
            waveformView.isHidden = true
            characterPlaceholder.isHidden = false
        } else {
            waveformView.isHidden = false
            characterPlaceholder.isHidden = true
            waveformView.style = WaveformStyle(rawValue: waveformStyle.lowercased()) ?? .bars
        }

        waveformView.accentColor = accentColor
        timerLabel.textColor = accentColor
    }

    func updateRMS(_ rms: Float) {
        waveformView.rms = rms
    }

    func showRecording() {
        stopPulse()
        recordingStartTime = Date()
        timerLabel.stringValue = "0:00"

        // Restore bars style if not a character style
        if !useCharacter {
            // Keep current waveform style — just ensure waveform visible
            waveformView.isHidden = false
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            let elapsed = Int(Date().timeIntervalSince(start))
            let minutes = elapsed / 60
            let seconds = elapsed % 60
            self.timerLabel.stringValue = "\(minutes):\(String(format: "%02d", seconds))"
        }
    }

    func showTranscribing() {
        timer?.invalidate()
        timer = nil

        if !useCharacter {
            waveformView.style = .dots
        }

        // Gently oscillate rms between 0.1 and 0.3
        pulsePhase = 0
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pulsePhase += 0.1
            let pulsedRMS = Float(0.2 + 0.1 * sin(self.pulsePhase))
            self.waveformView.rms = pulsedRMS
        }
    }

    // MARK: - Private helpers

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
    }

    deinit {
        timer?.invalidate()
        pulseTimer?.invalidate()
    }
}
