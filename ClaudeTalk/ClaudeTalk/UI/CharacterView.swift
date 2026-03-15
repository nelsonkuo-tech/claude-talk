import AppKit

class CharacterView: NSView {
    enum MouthState: Int {
        case closed = 0, small = 1, open = 2, thinking = 3
    }

    var character: String = "cat" {
        didSet { loadSprites() }
    }

    private var sprites: [NSImage] = []
    private var currentFrame: MouthState = .closed
    private var isThinking = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        loadSprites()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadSprites()
    }

    private func loadSprites() {
        sprites = (0...3).map { index in
            let assetName = "\(character)_\(index)"
            if let image = NSImage(named: assetName) {
                return image
            } else {
                return makePlaceholder(frame: index)
            }
        }
        needsDisplay = true
    }

    private func makePlaceholder(frame index: Int) -> NSImage {
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size)
        image.lockFocus()

        // Different gray levels per frame for visual distinction
        let grayLevels: [CGFloat] = [0.3, 0.45, 0.6, 0.75]
        let gray = grayLevels[min(index, grayLevels.count - 1)]
        NSColor(white: gray, alpha: 1.0).setFill()
        NSRect(origin: .zero, size: size).fill()

        // Draw a simple mouth indicator so frames are visually distinct
        NSColor(white: gray * 0.5, alpha: 1.0).setFill()
        let mouthHeights: [CGFloat] = [2, 4, 8, 6]
        let mouthHeight = mouthHeights[min(index, mouthHeights.count - 1)]
        let mouthWidth: CGFloat = index == 3 ? 12 : 14
        let mouthX = (32 - mouthWidth) / 2
        let mouthY: CGFloat = 8
        NSRect(x: mouthX, y: mouthY, width: mouthWidth, height: mouthHeight).fill()

        // Draw eyes (two small squares)
        NSColor(white: 0.1, alpha: 1.0).setFill()
        NSRect(x: 8, y: 20, width: 4, height: 4).fill()
        NSRect(x: 20, y: 20, width: 4, height: 4).fill()

        // Thinking frame: add ellipsis dots
        if index == 3 {
            NSColor(white: 0.9, alpha: 1.0).setFill()
            for dot in 0..<3 {
                NSRect(x: CGFloat(10 + dot * 5), y: 4, width: 2, height: 2).fill()
            }
        }

        image.unlockFocus()
        return image
    }

    func updateRMS(_ rms: Float) {
        guard !isThinking else { return }
        if rms < 0.01 {
            currentFrame = .closed
        } else if rms < 0.05 {
            currentFrame = .small
        } else {
            currentFrame = .open
        }
        needsDisplay = true
    }

    func showThinking() {
        isThinking = true
        currentFrame = .thinking
        needsDisplay = true
    }

    func reset() {
        isThinking = false
        currentFrame = .closed
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        // CRITICAL: No interpolation — keep pixel art crisp
        context.imageInterpolation = .none

        let frameIndex = currentFrame.rawValue
        guard frameIndex < sprites.count else { return }

        let sprite = sprites[frameIndex]
        // Draw sprite filling the view bounds (rendered at view size, no antialiasing)
        sprite.draw(in: bounds,
                    from: NSRect(origin: .zero, size: sprite.size),
                    operation: .sourceOver,
                    fraction: 1.0,
                    respectFlipped: true,
                    hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)])
    }
}
