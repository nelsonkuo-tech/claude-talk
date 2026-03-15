import AppKit

enum NotchState {
    case idle, recording, transcribing, success, error, discarded
}

class NotchOverlay {
    private var panel: NSPanel?
    private(set) var contentView: NotchContentView?

    private let pillWidth: CGFloat = 280
    private let pillHeight: CGFloat = 36
    private let cornerRadius: CGFloat = 20
    private let animationDuration: TimeInterval = 0.3

    private var restPosition: NSPoint = .zero
    private var showPosition: NSPoint = .zero

    var state: NotchState = .idle {
        didSet { handleStateChange(from: oldValue, to: state) }
    }

    private var hasNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }

    init() {
        setupPanel()
    }

    // MARK: - Panel Setup

    private func setupPanel() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.frame
        calculatePositions(screenFrame: screenFrame, safeAreaInsets: screen.safeAreaInsets)

        let initialFrame = NSRect(origin: restPosition, size: CGSize(width: pillWidth, height: pillHeight))
        let panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false

        // Create container view with rounded bottom corners only
        let containerView = NSView(frame: NSRect(origin: .zero, size: CGSize(width: pillWidth, height: pillHeight)))
        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = true
        containerView.layer?.cornerRadius = cornerRadius
        containerView.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]

        // Create content view
        let content = NotchContentView(frame: containerView.bounds)
        content.autoresizingMask = [.width, .height]
        containerView.addSubview(content)
        self.contentView = content

        panel.contentView = containerView
        self.panel = panel
    }

    private func calculatePositions(screenFrame: NSRect, safeAreaInsets: NSEdgeInsets) {
        let centerX = screenFrame.midX - pillWidth / 2

        if hasNotch {
            // Place pill directly below the notch safe area
            let yVisible = screenFrame.maxY - safeAreaInsets.top - pillHeight
            showPosition = NSPoint(x: centerX, y: yVisible)
        } else {
            // Place pill just below the top of screen with small gap
            let yVisible = screenFrame.maxY - pillHeight - 4
            showPosition = NSPoint(x: centerX, y: yVisible)
        }

        // Rest position: pill hidden above screen edge
        restPosition = NSPoint(x: showPosition.x, y: screenFrame.maxY + 2)
    }

    // MARK: - Panel Visibility

    private func showPanel() {
        guard let panel = panel else { return }

        // Reset to rest position before animating in
        var frame = panel.frame
        frame.origin = restPosition
        panel.setFrame(frame, display: false)

        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            var targetFrame = panel.frame
            targetFrame.origin = showPosition
            panel.animator().setFrame(targetFrame, display: true)
        }
    }

    private func hidePanel(animated: Bool = true) {
        guard let panel = panel else { return }

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                var targetFrame = panel.frame
                targetFrame.origin = restPosition
                panel.animator().setFrame(targetFrame, display: true)
            }, completionHandler: {
                panel.orderOut(nil)
            })
        } else {
            panel.orderOut(nil)
        }
    }

    // MARK: - Visual Style

    private func applyPillStyle(_ style: String) {
        guard let containerView = panel?.contentView else { return }

        // Remove any existing effect views
        for subview in containerView.subviews where subview is NSVisualEffectView {
            subview.removeFromSuperview()
        }

        if style == "frosted" {
            let effectView = NSVisualEffectView(frame: containerView.bounds)
            effectView.material = .dark
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.autoresizingMask = [.width, .height]
            effectView.wantsLayer = true

            // Insert behind content view
            containerView.addSubview(effectView, positioned: .below, relativeTo: contentView)
            containerView.layer?.backgroundColor = NSColor.clear.cgColor
        } else {
            // Solid black background
            containerView.layer?.backgroundColor = NSColor.black.cgColor
        }
    }

    // MARK: - State Handling

    private func handleStateChange(from oldState: NotchState, to newState: NotchState) {
        switch newState {
        case .idle:
            hidePanel()
        case .recording:
            showPanel()
            contentView?.showRecording()
        case .transcribing:
            contentView?.showTranscribing()
        case .success:
            NSSound(named: "Pop")?.play()
            hidePanel()
        case .error:
            NSSound(named: "Basso")?.play()
            hidePanel()
        case .discarded:
            hidePanel(animated: false)
        }
    }

    // MARK: - Public Interface

    func updateRMS(_ rms: Float) {
        contentView?.updateRMS(rms)
    }

    func configure(waveformStyle: String, accentColor: NSColor, pillStyle: String) {
        contentView?.configure(waveformStyle: waveformStyle, accentColor: accentColor)
        applyPillStyle(pillStyle)
    }
}

// NotchContentView is defined in NotchContentView.swift
