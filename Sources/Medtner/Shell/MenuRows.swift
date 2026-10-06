import AppKit
import QuartzCore

enum MenuStyle {
    static let width: CGFloat = 300
    static let inset: CGFloat = 14

    static func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular,
                     color: NSColor = .labelColor, mono: Bool = false) -> NSAttributedString {
        let font = mono
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    static func soften(_ path: NSBezierPath, corner: CGFloat, color: NSColor) {
        color.setFill()
        color.setStroke()
        path.lineJoinStyle = .round
        path.lineWidth = corner
        path.fill()
        path.stroke()
    }

    static func playPause(in rect: NSRect, progress: CGFloat) -> NSBezierPath {
        let w = rect.width, h = rect.height
        if progress < 0.02 {
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: rect.minX + 0.08 * w, y: rect.minY))
            triangle.line(to: NSPoint(x: rect.maxX, y: rect.midY))
            triangle.line(to: NSPoint(x: rect.minX + 0.08 * w, y: rect.maxY))
            triangle.close()
            return triangle
        }
        func mix(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) -> NSPoint {
            NSPoint(x: rect.minX + (a.0 + (b.0 - a.0) * progress) * w,
                    y: rect.minY + (a.1 + (b.1 - a.1) * progress) * h)
        }
        let left = [
            mix((0.08, 0), (0.12, 0.02)), mix((0.54, 0.26), (0.38, 0.02)),
            mix((0.54, 0.74), (0.38, 0.98)), mix((0.08, 1), (0.12, 0.98)),
        ]
        let right = [
            mix((0.54, 0.26), (0.62, 0.02)), mix((1, 0.5), (0.88, 0.02)),
            mix((1, 0.5), (0.88, 0.98)), mix((0.54, 0.74), (0.62, 0.98)),
        ]
        let path = NSBezierPath()
        for quad in [left, right] {
            path.move(to: quad[0])
            quad.dropFirst().forEach { path.line(to: $0) }
            path.close()
        }
        return path
    }

    static func skip(in rect: NSRect, forward: Bool) -> NSBezierPath {
        let w = rect.width, h = rect.height
        func x(_ f: CGFloat) -> CGFloat { rect.minX + (forward ? f : 1 - f) * w }
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x(0.04), y: rect.minY + 0.06 * h))
        path.line(to: NSPoint(x: x(0.7), y: rect.midY))
        path.line(to: NSPoint(x: x(0.04), y: rect.minY + 0.94 * h))
        path.close()
        let barX = forward ? x(0.84) : x(0.96)
        path.appendRect(NSRect(x: barX, y: rect.minY + 0.06 * h, width: 0.12 * w, height: 0.88 * h))
        return path
    }
}

class MenuRow: NSView {
    private(set) var hovered = false
    private(set) var pointer: NSPoint?

    override var isFlipped: Bool { true }

    init(height: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuStyle.width, height: height))
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { track(event) }
    override func mouseMoved(with event: NSEvent) { track(event) }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        pointer = nil
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            hovered = false
            pointer = nil
        }
    }

    private func track(_ event: NSEvent) {
        hovered = true
        pointer = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    func hoverFill(_ rect: NSRect, lit: Bool) {
        guard lit else { return }
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
    }
}

@MainActor
final class NowPlayingRow: MenuRow {
    private let player: Player
    private var scrub: Double?

    init(player: Player) {
        self.player = player
        super.init(height: 98)
    }

    required init?(coder: NSCoder) { nil }

    private var barRect: NSRect {
        NSRect(x: MenuStyle.inset, y: 72, width: bounds.width - MenuStyle.inset * 2, height: 4)
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = MenuStyle.inset
        let art = NSRect(x: inset, y: 10, width: 50, height: 50)
        let clip = NSBezierPath(roundedRect: art, xRadius: 9, yRadius: 9)
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        if let image = player.track == nil ? Palette.placeholder : player.artwork {
            image.draw(in: art, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        } else {
            NSColor.labelColor.withAlphaComponent(0.1).setFill()
            art.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        let textX = art.maxX + 12
        let textWidth = bounds.width - textX - inset
        MenuStyle.text(player.track?.name ?? "Nothing playing", size: 14, weight: .semibold)
            .draw(with: NSRect(x: textX, y: 16, width: textWidth, height: 18), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        MenuStyle.text(player.track?.artistLine ?? "Press play to wake the speaker", size: 12, color: .secondaryLabelColor)
            .draw(with: NSRect(x: textX, y: 35, width: textWidth, height: 16), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

        let bar = barRect
        let fraction = CGFloat(scrub ?? player.fraction())
        let lit = hovered && (pointer.map { $0.y > 62 } ?? false) || scrub != nil
        let thickness: CGFloat = lit ? 6 : 4
        let track = NSRect(x: bar.minX, y: bar.midY - thickness / 2, width: bar.width, height: thickness)
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: track, xRadius: thickness / 2, yRadius: thickness / 2).fill()
        player.accent.setFill()
        let filled = NSRect(x: track.minX, y: track.minY, width: max(thickness, track.width * fraction), height: thickness)
        NSBezierPath(roundedRect: filled, xRadius: thickness / 2, yRadius: thickness / 2).fill()

        let elapsed = Int(Double(player.durationMs) * Double(fraction))
        let remaining = player.durationMs - elapsed
        let times = player.track == nil ? ("", "") : (formatTime(elapsed), "-" + formatTime(remaining))
        MenuStyle.text(times.0, size: 10, weight: .medium, color: .tertiaryLabelColor, mono: true)
            .draw(at: NSPoint(x: bar.minX, y: 80))
        let right = MenuStyle.text(times.1, size: 10, weight: .medium, color: .tertiaryLabelColor, mono: true)
        right.draw(at: NSPoint(x: bar.maxX - right.size().width, y: 80))
    }

    private func fraction(at event: NSEvent) -> Double {
        let point = convert(event.locationInWindow, from: nil)
        return Double(min(max((point.x - barRect.minX) / barRect.width, 0), 1))
    }

    override func mouseDown(with event: NSEvent) {
        guard convert(event.locationInWindow, from: nil).y > 62, player.track != nil else { return }
        scrub = fraction(at: event)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard scrub != nil else { return }
        scrub = fraction(at: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard scrub != nil else { return }
        player.seek(to: fraction(at: event))
        scrub = nil
        needsDisplay = true
    }
}

@MainActor
final class TransportRow: MenuRow {
    private let player: Player
    private var morph: CGFloat = 0
    private var morphTimer: Timer?

    init(player: Player) {
        self.player = player
        super.init(height: 44)
        morph = player.isPlaying ? 1 : 0
    }

    required init?(coder: NSCoder) { nil }

    private enum Control: CaseIterable { case shuffle, previous, play, next, repeating }

    private func rect(for control: Control) -> NSRect {
        let mid = bounds.midX
        switch control {
        case .shuffle: return NSRect(x: MenuStyle.inset - 4, y: 8, width: 28, height: 28)
        case .previous: return NSRect(x: mid - 66, y: 6, width: 36, height: 32)
        case .play: return NSRect(x: mid - 20, y: 4, width: 40, height: 36)
        case .next: return NSRect(x: mid + 30, y: 6, width: 36, height: 32)
        case .repeating: return NSRect(x: bounds.width - MenuStyle.inset - 24, y: 8, width: 28, height: 28)
        }
    }

    private func control(at point: NSPoint?) -> Control? {
        guard let point else { return nil }
        return Control.allCases.first { rect(for: $0).insetBy(dx: -3, dy: -3).contains(point) }
    }

    func sync() {
        let target: CGFloat = player.isPlaying ? 1 : 0
        guard target != morph, morphTimer == nil else { return needsDisplay = true }
        let from = morph
        let start = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                let raw = min(1, (CACurrentMediaTime() - start) / 0.22)
                let eased = 1 - pow(1 - raw, 3)
                self.morph = from + (target - from) * CGFloat(eased)
                self.needsDisplay = true
                self.displayIfNeeded()
                if raw >= 1 {
                    timer.invalidate()
                    self.morphTimer = nil
                    self.sync()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        morphTimer = timer
    }

    override func draw(_ dirtyRect: NSRect) {
        let hover = control(at: pointer)
        for control in Control.allCases {
            let r = rect(for: control)
            hoverFill(r, lit: hover == control)
            NSGraphicsContext.saveGraphicsState()
            if hover == control {
                let grow = NSAffineTransform()
                grow.translateX(by: r.midX, yBy: r.midY)
                grow.scale(by: 1.15)
                grow.translateX(by: -r.midX, yBy: -r.midY)
                grow.concat()
            }
            defer { NSGraphicsContext.restoreGraphicsState() }
            let color = NSColor.labelColor
            switch control {
            case .shuffle:
                symbol("shuffle", in: r, on: player.shuffle)
            case .repeating:
                symbol(player.repeatMode.symbol, in: r, on: player.repeatMode != .off)
            case .previous, .next:
                let glyph = NSRect(x: r.midX - 7.5, y: r.midY - 7, width: 15, height: 14)
                MenuStyle.soften(MenuStyle.skip(in: glyph, forward: control == .next), corner: 1.4, color: color)
            case .play:
                let glyph = NSRect(x: r.midX - 8, y: r.midY - 9, width: 16, height: 18)
                MenuStyle.soften(MenuStyle.playPause(in: glyph, progress: morph), corner: 1.6, color: color)
            }
        }
    }

    private func symbol(_ name: String, in r: NSRect, on: Bool) {
        let tint: NSColor = on ? player.accent : .secondaryLabelColor
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        image.draw(in: NSRect(x: r.midX - image.size.width / 2, y: r.midY - image.size.height / 2,
                              width: image.size.width, height: image.size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func mouseUp(with event: NSEvent) {
        switch control(at: convert(event.locationInWindow, from: nil)) {
        case .shuffle: player.toggleShuffle()
        case .repeating: player.cycleRepeat()
        case .previous: player.previous()
        case .play: player.togglePlay()
        case .next: player.next()
        case nil: return
        }
        sync()
    }
}

@MainActor
final class VolumeRow: MenuRow {
    private let player: Player
    private var dragging = false

    init(player: Player) {
        self.player = player
        super.init(height: 30)
    }

    required init?(coder: NSCoder) { nil }

    private var trackRect: NSRect {
        NSRect(x: MenuStyle.inset + 26, y: 11, width: bounds.width - MenuStyle.inset * 2 - 26, height: 8)
    }

    override func draw(_ dirtyRect: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor]))
        if let image = NSImage(systemSymbolName: "speaker.wave.2.fill", variableValue: Double(player.volume) / 100,
                               accessibilityDescription: "Volume")?.withSymbolConfiguration(config) {
            image.draw(in: NSRect(x: MenuStyle.inset, y: bounds.midY - image.size.height / 2,
                                  width: image.size.width, height: image.size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let track = trackRect
        let thickness: CGFloat = hovered || dragging ? 6 : 4
        let line = NSRect(x: track.minX, y: track.midY - thickness / 2, width: track.width, height: thickness)
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: line, xRadius: thickness / 2, yRadius: thickness / 2).fill()
        NSColor.labelColor.setFill()
        let filled = NSRect(x: line.minX, y: line.minY, width: max(thickness, line.width * CGFloat(player.volume) / 100), height: thickness)
        NSBezierPath(roundedRect: filled, xRadius: thickness / 2, yRadius: thickness / 2).fill()
    }

    private func apply(_ event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        player.setVolume(Int(((x - trackRect.minX) / trackRect.width) * 100))
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        dragging = true
        apply(event)
    }

    override func mouseDragged(with event: NSEvent) { apply(event) }

    override func mouseUp(with event: NSEvent) {
        apply(event)
        dragging = false
        needsDisplay = true
    }
}
