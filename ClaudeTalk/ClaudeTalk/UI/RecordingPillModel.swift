import SwiftUI

enum RecordingUIState {
    case idle, recording, transcribing, done, error
}

@Observable
class RecordingPillModel {
    var state: RecordingUIState = .idle
    var barLevels: [CGFloat] = Array(repeating: 0.08, count: 7)
    var isVisible: Bool = false
    var glassStyle: String = "auto"  // "auto", "light", "dark"

    private var rms: Float = 0
    private var spectrumBands: [Float] = Array(repeating: 0, count: 7)
    private var pulseTimer: Timer?
    private var pulsePhase: Double = 0
    private var animationTimer: Timer?

    func updateRMS(_ newRMS: Float) {
        rms = newRMS
    }

    func updateSpectrum(_ bands: [Float]) {
        spectrumBands = bands
    }

    func transitionTo(_ newState: RecordingUIState) {
        stopPulse()

        switch newState {
        case .idle:
            withAnimation(.easeIn(duration: 0.25)) {
                isVisible = false
            }
            state = .idle

        case .recording:
            state = .recording
            startAnimationTimer()
            withAnimation(.easeOut(duration: 0.25)) {
                isVisible = true
            }

        case .transcribing:
            state = .transcribing
            startPulse()

        case .done:
            withAnimation(.easeInOut(duration: 0.2)) {
                state = .done
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.transitionTo(.idle)
            }

        case .error:
            withAnimation(.easeInOut(duration: 0.2)) {
                state = .error
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.transitionTo(.idle)
            }
        }
    }

    // MARK: - Private

    private func recalcBars() {
        let count = barLevels.count
        let silenceThreshold: Float = 0.015

        for i in 0..<count {
            let target: CGFloat

            if rms < silenceThreshold {
                target = 0.08
            } else {
                // Use real FFT spectrum band value
                let band = i < spectrumBands.count ? spectrumBands[i] : 0
                target = CGFloat(max(0.1, min(1.0, band)))
            }

            // Smooth: fast attack, gentle release
            let smoothing: CGFloat = target > barLevels[i] ? 0.65 : 0.85
            barLevels[i] = barLevels[i] * smoothing + target * (1 - smoothing)
        }
    }

    private func startAnimationTimer() {
        stopAnimationTimer()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.recalcBars()
        }
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func startPulse() {
        pulsePhase = 0
        startAnimationTimer()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pulsePhase += 0.08
            let pulse = Float(0.15 + 0.1 * sin(self.pulsePhase))
            self.spectrumBands = (0..<7).map { i in
                pulse + Float.random(in: -0.03...0.03)
            }
            self.rms = pulse
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        stopAnimationTimer()
    }

    deinit {
        pulseTimer?.invalidate()
        animationTimer?.invalidate()
    }
}
