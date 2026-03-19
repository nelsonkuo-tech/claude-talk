import SwiftUI

enum RecordingUIState {
    case idle, recording, transcribing, done, error
}

@Observable
class RecordingPillModel {
    var state: RecordingUIState = .idle
    var barLevels: [CGFloat] = Array(repeating: 0.15, count: 7)
    var isVisible: Bool = false

    private var rms: Float = 0
    private var pulseTimer: Timer?
    private var pulsePhase: Double = 0

    func updateRMS(_ newRMS: Float) {
        rms = newRMS
        recalcBars()
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
            // Auto-hide after brief delay
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
        for i in 0..<count {
            let halfCount = Float(count - 1) / 2
            let dist = abs(Float(i) - halfCount) / halfCount
            let envelope = 1.0 - dist * 0.4
            let amplitude = 0.3 + rms * 0.7
            let target = CGFloat(envelope * amplitude)
            barLevels[i] = barLevels[i] * 0.5 + target * 0.5
        }
    }

    private func startPulse() {
        pulsePhase = 0
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pulsePhase += 0.1
            let pulsedRMS = Float(0.2 + 0.1 * sin(self.pulsePhase))
            self.updateRMS(pulsedRMS)
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
    }

    deinit {
        pulseTimer?.invalidate()
    }
}
