import AppKit

enum WaveformStyle: String, CaseIterable {
    case bars, dots, line
}

class WaveformView: NSView {
    var style: WaveformStyle = .bars { didSet { needsDisplay = true } }
    var accentColor: NSColor = .white { didSet { needsDisplay = true } }
    var rms: Float = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        accentColor.setFill()
        accentColor.setStroke()

        switch style {
        case .bars:
            drawBars(ctx: ctx)
        case .dots:
            drawDots(ctx: ctx)
        case .line:
            drawLine(ctx: ctx)
        }
    }

    // MARK: - Bars

    private func drawBars(ctx: CGContext) {
        let barCount = 7
        let barWidth: CGFloat = 3
        let gap: CGFloat = 2
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
        let startX = (bounds.width - totalWidth) / 2
        let minHeight = bounds.height * 0.15
        let maxHeight = bounds.height

        for i in 0..<barCount {
            let halfCount = Float(barCount - 1) / 2
            let distFromCenter = abs(Float(i) - halfCount) / halfCount
            let envelope = 1.0 - Double(distFromCenter) * 0.4
            let amplitude = 0.4 + Double(rms) * 0.6
            let heightFactor = envelope * amplitude
            let barHeight = max(minHeight, CGFloat(heightFactor) * maxHeight)
            let x = startX + CGFloat(i) * (barWidth + gap)
            let y = (bounds.height - barHeight) / 2

            let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
            ctx.addPath(path)
            ctx.fillPath()
        }
    }

    // MARK: - Dots

    private func drawDots(ctx: CGContext) {
        let dotCount = 5
        let maxRadius: CGFloat = 4
        let totalWidth = bounds.width
        let spacing = totalWidth / CGFloat(dotCount + 1)
        let centerY = bounds.height / 2

        for i in 0..<dotCount {
            let halfDotCount = Float(dotCount - 1) / 2 + 0.001
            let distFromCenter = abs(Float(i) - Float(dotCount - 1) / 2) / halfDotCount
            let envelope = 1.0 - Double(distFromCenter) * 0.3
            let amplitude = 0.4 + Double(rms) * 0.6
            let sizeFactor = CGFloat(envelope * amplitude)
            let radius = max(1.5, maxRadius * sizeFactor)
            let x = spacing * CGFloat(i + 1)

            let rect = CGRect(x: x - radius, y: centerY - radius, width: radius * 2, height: radius * 2)
            ctx.fillEllipse(in: rect)
        }
    }

    // MARK: - Line

    private func drawLine(ctx: CGContext) {
        let pointCount = 20
        let amplitude = bounds.height * 0.4 * CGFloat(rms)
        let centerY = bounds.height / 2
        let time = CACurrentMediaTime()

        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        var points: [CGPoint] = []
        for i in 0..<pointCount {
            let t = Double(i) / Double(pointCount - 1)
            let x = bounds.width * CGFloat(t)
            let phase = t * .pi * 2 + time * 3
            let y = centerY + amplitude * CGFloat(sin(phase))
            points.append(CGPoint(x: x, y: y))
        }

        ctx.move(to: points[0])
        for p in points.dropFirst() {
            ctx.addLine(to: p)
        }
        ctx.strokePath()
    }
}
