import AppKit
import SwiftUI

class NotchOverlay {
    private var panel: NSPanel?
    let model = RecordingPillModel()

    private let panelWidth: CGFloat = 300
    private let panelHeight: CGFloat = 80
    private let animationDuration: TimeInterval = 0.3

    init() {
        setupPanel()
    }

    // MARK: - Panel Setup

    private func setupPanel() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        // Position: centered horizontally, directly below the notch
        let notchHeight = screen.safeAreaInsets.top
        let windowOrigin = NSPoint(
            x: screenFrame.origin.x + (screenFrame.width - panelWidth) / 2,
            y: screenFrame.maxY - notchHeight - panelHeight - 4
        )
        let windowFrame = NSRect(
            origin: windowOrigin,
            size: CGSize(width: panelWidth, height: panelHeight)
        )

        let panel = NSPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        panel.level = NSWindow.Level(Int(CGShieldingWindowLevel()) + 1)
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false

        let swiftUIView = RecordingPillView(model: model)
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.frame = NSRect(origin: .zero, size: windowFrame.size)
        hostingView.autoresizingMask = [.width, .height]

        panel.contentView = hostingView
        self.panel = panel

        NSLog("[ClaudeTalk] NotchOverlay panel: frame=%@, notchHeight=%.0f",
              NSStringFromRect(windowFrame), notchHeight)
    }

    // MARK: - State

    var state: NotchState = .idle {
        didSet { handleStateChange(from: oldValue, to: state) }
    }

    private func handleStateChange(from oldState: NotchState, to newState: NotchState) {
        switch newState {
        case .idle:
            model.transitionTo(.idle)
            hidePanel()

        case .recording:
            model.transitionTo(.recording)
            showPanel()

        case .transcribing:
            model.transitionTo(.transcribing)

        case .polishing:
            model.transitionTo(.polishing)

        case .success:
            model.transitionTo(.done)
            NSSound(named: "Pop")?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.hidePanel()
            }

        case .error:
            model.transitionTo(.error)
            NSSound(named: "Basso")?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.hidePanel()
            }

        case .discarded:
            model.transitionTo(.idle)
            hidePanel(animated: false)
        }
    }

    // MARK: - Panel Visibility

    private func showPanel() {
        guard let panel = panel else {
            NSLog("[ClaudeTalk] showPanel: panel is nil!")
            return
        }
        repositionPanel()
        panel.alphaValue = 1
        // orderFrontRegardless works even when app is not active (e.g. fullscreen other app)
        panel.orderFrontRegardless()
        // Re-assert window level every time — macOS can demote it after space switches
        panel.level = NSWindow.Level(Int(CGShieldingWindowLevel()) + 1)
        NSLog("[ClaudeTalk] showPanel: visible=%d, onScreen=%d, level=%d, frame=%@",
              panel.isVisible ? 1 : 0,
              panel.screen != nil ? 1 : 0,
              panel.level.rawValue,
              NSStringFromRect(panel.frame))
    }

    private func repositionPanel() {
        guard let panel = panel else { return }
        // Use the screen that has keyboard focus, fall back to main
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let activeScreen = screen else { return }
        let screenFrame = activeScreen.frame
        let notchHeight = activeScreen.safeAreaInsets.top
        let origin = NSPoint(
            x: screenFrame.origin.x + (screenFrame.width - panelWidth) / 2,
            y: screenFrame.maxY - notchHeight - panelHeight - 4
        )
        panel.setFrameOrigin(origin)
    }

    private func hidePanel(animated: Bool = true) {
        guard let panel = panel else { return }

        if !animated {
            panel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    // MARK: - Public Interface

    func updateRMS(_ rms: Float) {
        model.updateRMS(rms)
    }

    func configure(waveformStyle: String, accentColor: NSColor, pillStyle: String) {
        // Glass effect handles styling natively
    }
}

enum NotchState: Int {
    case idle = 0, recording = 1, transcribing = 2, polishing = 3, success = 4, error = 5, discarded = 6
}
