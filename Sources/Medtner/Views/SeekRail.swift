import AppKit
import QuartzCore
import SwiftUI

final class RailLayerView: NSView {
    var stopListening: (() -> Void)?
    private let host = CALayer()
    private let core = CALayer()
    private let waves = (0..<3).map { _ in CAShapeLayer() }
    private let knob = CALayer()
    private let bubble = CALayer()
    private let label = CATextLayer()
    private var bubbleTimer: Timer?
    private var showingTime = false
    private var fraction: Double = 0
    private var playing = false
    private var rolling = false
    private var grabbed = false
    private var remaining: Double = 0
    private var duration: Double = 0
    private var anchorTime = CACurrentMediaTime()
    private var slot: CGFloat = 15
    private var builtHeight: CGFloat = 0
    private var smoothed: [CGFloat] = [0, 0, 0]

    private static let knobSize = CGSize(width: 22, height: 4)
    private static let gap: CGFloat = 5
    private static let shapes: [(amp: CGFloat, k: CGFloat, phase: CGFloat, period: Double)] = [
        (11, 9, 0.3, 1.9), (8.5, 13, 1.9, 2.5), (6.5, 17, 3.1, 3.3),
    ]
    private static let restScale: CGFloat = 0.3

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        host.anchorPoint = CGPoint(x: 0.5, y: 0)
        host.shadowOffset = .zero
        host.shadowRadius = 7
        host.shadowOpacity = 0.8
        for wave in waves {
            wave.compositingFilter = "screenBlendMode"
            wave.transform = CATransform3DMakeScale(Self.restScale, 1, 1)
            host.addSublayer(wave)
        }
        core.backgroundColor = NSColor(white: 1, alpha: 0.8).cgColor
        host.addSublayer(core)
        layer?.addSublayer(host)
        knob.backgroundColor = NSColor.white.cgColor
        knob.cornerRadius = Self.knobSize.height / 2
        knob.shadowOffset = .zero
        knob.shadowRadius = 8
        knob.shadowOpacity = 0.9
        knob.bounds = CGRect(origin: .zero, size: Self.knobSize)
        knob.shadowPath = CGPath(roundedRect: knob.bounds, cornerWidth: 2, cornerHeight: 2, transform: nil)
        layer?.addSublayer(knob)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.fontSize = 11
        label.foregroundColor = NSColor.black.cgColor
        label.alignmentMode = .center
        bubble.addSublayer(label)
        bubble.opacity = 0
        bubble.anchorPoint = CGPoint(x: 0, y: 0.5)
        bubble.transform = CATransform3DMakeScale(0.6, 0.6, 1)
        bubble.position = CGPoint(x: Self.knobSize.width + 8, y: Self.knobSize.height / 2)
        knob.addSublayer(bubble)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        label.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateRoll()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func showTime(_ visible: Bool) {
        guard visible != showingTime else { return }
        showingTime = visible
        bubbleTimer?.invalidate()
        bubbleTimer = nil
        if visible {
            refreshBubble()
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshBubble() }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            bubbleTimer = timer
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.2))
        bubble.opacity = visible ? 1 : 0
        bubble.transform = visible ? CATransform3DIdentity : CATransform3DMakeScale(0.6, 0.6, 1)
        CATransaction.commit()
    }

    private func refreshBubble() {
        let seconds = Int(currentFraction() * duration)
        let text = String(format: "%d:%02d", seconds / 60, seconds % 60)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width) + 12
        let height: CGFloat = 19
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        label.string = text
        label.frame = CGRect(x: 0, y: 3, width: width, height: 14)
        bubble.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        bubble.cornerRadius = height / 2
        CATransaction.commit()
    }

    func apply(fraction: Double, playing: Bool, durationMs: Int, accent: NSColor, palette: [NSColor], dragging: Double?, slot: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let colors = palette.isEmpty ? [accent] : palette
        for (i, wave) in waves.enumerated() {
            wave.fillColor = colors[i % colors.count].withAlphaComponent(0.85).cgColor
        }
        host.shadowColor = accent.cgColor
        knob.shadowColor = accent.cgColor
        bubble.backgroundColor = accent.cgColor
        CATransaction.commit()
        self.slot = slot

        if let dragging {
            drag(to: dragging)
            return
        }
        let released = grabbed
        grabbed = false

        let clamped = min(max(fraction, 0), 1)
        let drift = abs(currentFraction() - clamped) * Double(durationMs) / 1000
        let changed = released || playing != self.playing || drift > 0.6
        guard changed else { return }
        self.fraction = clamped
        self.playing = playing
        self.duration = Double(durationMs) / 1000
        self.remaining = duration * (1 - clamped)
        anchorTime = CACurrentMediaTime()
        restart()
        updateRoll()
    }

    func receive(_ levels: [Float]) {
        guard playing, !grabbed, window?.occlusionState.contains(.visible) == true else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.09)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        for (i, wave) in waves.enumerated() {
            let target = CGFloat(i < levels.count ? levels[i] : 0)
            smoothed[i] += (target - smoothed[i]) * (target > smoothed[i] ? 0.6 : 0.15)
            wave.transform = CATransform3DMakeScale(0.5 + smoothed[i] * 0.9, 1, 1)
        }
        CATransaction.commit()
    }

    private func drag(to target: Double) {
        if !grabbed {
            grabbed = true
            knob.removeAnimation(forKey: "progress")
            host.removeAnimation(forKey: "progress")
        }
        let y = centerY(for: min(max(target, 0), 1))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        knob.position = CGPoint(x: bounds.midX, y: y)
        host.transform = CATransform3DMakeScale(1, stretch(at: y), 1)
        CATransaction.commit()
    }

    private func updateRoll() {
        let shouldRoll = playing && window != nil
        guard shouldRoll != rolling else { return }
        rolling = shouldRoll
        if shouldRoll {
            for (i, wave) in waves.enumerated() {
                let shape = Self.shapes[i]
                let frames = 12
                let roll = CAKeyframeAnimation(keyPath: "path")
                roll.values = (0...frames).map { step in
                    wavePath(shape: shape, phase: shape.phase + .pi * CGFloat(step) / CGFloat(frames))
                }
                roll.duration = shape.period
                roll.repeatCount = .infinity
                roll.calculationMode = .linear
                wave.add(roll, forKey: "roll")
            }
        } else {
            smoothed = [0, 0, 0]
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.6)
            for wave in waves {
                wave.removeAnimation(forKey: "roll")
                wave.transform = CATransform3DMakeScale(Self.restScale, 1, 1)
            }
            CATransaction.commit()
        }
    }

    private func wavePath(shape: (amp: CGFloat, k: CGFloat, phase: CGFloat, period: Double), phase: CGFloat) -> CGPath {
        let height = bounds.height
        let mid = bounds.midX
        let steps = 140
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in 0...steps {
            let u = CGFloat(i) / CGFloat(steps)
            let rise = 0.15 + 0.85 * pow(u, 2.2)
            let envelope = rise * pow(min(1, (1 - u) * 9), 0.7) * min(1, u * 30)
            let d = shape.amp * envelope * abs(sin(shape.k * (u * 4 - 2) + phase))
            left.append(CGPoint(x: mid - d, y: u * height))
            right.append(CGPoint(x: mid + d, y: u * height))
        }
        let path = CGMutablePath()
        path.addLines(between: left + right.reversed())
        path.closeSubpath()
        return path
    }

    private func currentFraction() -> Double {
        guard playing, remaining > 0 else { return fraction }
        let elapsed = CACurrentMediaTime() - anchorTime
        return min(1, fraction + (1 - fraction) * elapsed / remaining)
    }

    private func centerY(for fraction: Double) -> CGFloat {
        slot / 2 + (bounds.height - slot) * CGFloat(fraction)
    }

    private func stretch(at y: CGFloat) -> CGFloat {
        max(0.0001, (y - Self.gap) / max(bounds.height, 1))
    }

    override func layout() {
        super.layout()
        if bounds.height != builtHeight {
            builtHeight = bounds.height
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            host.bounds = bounds
            host.position = CGPoint(x: bounds.midX, y: 0)
            core.frame = CGRect(x: bounds.midX - 0.4, y: 0, width: 0.8, height: bounds.height)
            for (i, wave) in waves.enumerated() {
                wave.bounds = bounds
                wave.position = CGPoint(x: bounds.midX, y: bounds.midY)
                wave.path = wavePath(shape: Self.shapes[i], phase: Self.shapes[i].phase)
            }
            CATransaction.commit()
            if rolling {
                rolling = false
                updateRoll()
            }
        }
        guard !grabbed else { return }
        fraction = currentFraction()
        remaining = duration * (1 - fraction)
        anchorTime = CACurrentMediaTime()
        restart()
    }

    private func restart() {
        let start = centerY(for: fraction)
        let end = centerY(for: 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        knob.removeAnimation(forKey: "progress")
        host.removeAnimation(forKey: "progress")
        knob.position = CGPoint(x: bounds.midX, y: start)
        host.transform = CATransform3DMakeScale(1, stretch(at: start), 1)
        CATransaction.commit()

        guard playing, remaining > 0.05 else { return }
        let move = CABasicAnimation(keyPath: "position.y")
        move.fromValue = start
        move.toValue = end
        move.duration = remaining
        move.fillMode = .forwards
        move.isRemovedOnCompletion = false
        knob.add(move, forKey: "progress")

        let grow = CABasicAnimation(keyPath: "transform.scale.y")
        grow.fromValue = stretch(at: start)
        grow.toValue = stretch(at: end)
        grow.duration = remaining
        grow.fillMode = .forwards
        grow.isRemovedOnCompletion = false
        host.add(grow, forKey: "progress")
    }
}

struct RailLayer: NSViewRepresentable {
    let player: Player
    let fraction: Double
    let playing: Bool
    let durationMs: Int
    let accent: NSColor
    let palette: [NSColor]
    let dragging: Double?
    let slot: CGFloat
    let showTime: Bool

    func makeNSView(context: Context) -> RailLayerView {
        let view = RailLayerView(frame: .zero)
        let audio = player.engine.audio
        let token = audio.observeLevels { [weak view] levels in
            DispatchQueue.main.async { view?.receive(levels) }
        }
        view.stopListening = { [weak audio] in audio?.stopObservingLevels(token) }
        return view
    }

    func updateNSView(_ view: RailLayerView, context: Context) {
        view.apply(fraction: fraction, playing: playing, durationMs: durationMs, accent: accent,
                   palette: palette, dragging: dragging, slot: slot)
        view.showTime(showTime)
    }

    static func dismantleNSView(_ view: RailLayerView, coordinator: ()) {
        view.stopListening?()
    }
}

struct SeekRail: View {
    @Bindable var player: Player
    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        GeometryReader { geo in
            let knob: CGFloat = 15
            let travel = geo.size.height - knob
            let _ = player.progressEpoch
            let live = player.fraction()

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color(white: 0.32))
                    .frame(width: hovering ? 2 : 1.5)
                    .frame(maxHeight: .infinity)

                RailLayer(player: player, fraction: live, playing: player.isPlaying, durationMs: player.durationMs,
                          accent: player.accent, palette: player.palette,
                          dragging: dragFraction.map { min(max($0, 0), 1) }, slot: knob,
                          showTime: hovering && dragFraction == nil)
            }
            .frame(width: geo.size.width)
            .overlay(alignment: .topLeading) {
                if let dragFraction {
                    let y = travel * CGFloat(min(max(dragFraction, 0), 1))
                    Text(formatTime(Int(Double(player.durationMs) * dragFraction)))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(player.accentColor))
                        .fixedSize()
                        .offset(x: geo.size.width / 2 + 19, y: y - 2)
                        .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .pointerStyle(.link)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragFraction = Double((value.location.y - knob / 2) / travel)
                    }
                    .onEnded { value in
                        let target = Double((value.location.y - knob / 2) / travel)
                        player.seek(to: target)
                        dragFraction = nil
                    }
            )
            .onHover { hover in withAnimation(.spring(response: 0.25)) { hovering = hover } }
        }
        .frame(width: 26)
    }
}
