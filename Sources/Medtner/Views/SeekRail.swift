import AppKit
import QuartzCore
import SwiftUI

final class RailLayerView: NSView {
    var stopListening: (() -> Void)?
    private let track = CAShapeLayer()
    private let fill = CALayer()
    private let knob = CALayer()
    private let drop = CALayer()
    private let bubble = CALayer()
    private let label = CATextLayer()
    private var bubbleTimer: Timer?
    private var relaxWork: DispatchWorkItem?
    private var showingTime = false
    private var fraction: Double = 0
    private var playing = false
    private var remaining: Double = 0
    private var duration: Double = 0
    private var anchorTime = CACurrentMediaTime()
    private var knobSize: CGFloat = 15
    private var lineWidth: CGFloat = 5
    private var grabbed = false
    private var lastDrag: (y: CGFloat, time: CFTimeInterval)?
    private var bass: CGFloat = 0
    private var lastBeat = Date.distantPast

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        track.fillColor = nil
        track.strokeColor = NSColor(white: 1, alpha: 0.22).cgColor
        track.lineWidth = 2
        track.lineCap = .round
        track.lineDashPattern = [3, 6]
        fill.anchorPoint = CGPoint(x: 0.5, y: 0)
        drop.shadowOpacity = 0.3
        drop.shadowRadius = 6
        drop.shadowOffset = .zero
        knob.addSublayer(drop)
        layer?.addSublayer(track)
        layer?.addSublayer(fill)
        layer?.addSublayer(knob)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.fontSize = 11
        label.foregroundColor = NSColor.black.cgColor
        label.alignmentMode = .center
        bubble.addSublayer(label)
        bubble.opacity = 0
        bubble.anchorPoint = CGPoint(x: 0, y: 0.5)
        bubble.transform = CATransform3DMakeScale(0.6, 0.6, 1)
        knob.addSublayer(bubble)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        label.contentsScale = window?.backingScaleFactor ?? 2
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
        bubble.position = CGPoint(x: knobSize + 8, y: knobSize / 2)
        CATransaction.commit()
    }

    func apply(fraction: Double, playing: Bool, durationMs: Int, color: NSColor, dragging: Double?, knobSize: CGFloat, lineWidth: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.backgroundColor = color.cgColor
        drop.backgroundColor = color.cgColor
        drop.shadowColor = color.cgColor
        bubble.backgroundColor = color.cgColor
        CATransaction.commit()

        if let dragging {
            drag(to: dragging)
            return
        }
        let released = grabbed
        if released { release() }

        let clamped = min(max(fraction, 0), 1)
        let drift = abs(currentFraction() - clamped) * Double(durationMs) / 1000
        let changed = released || playing != self.playing || drift > 0.6 || knobSize != self.knobSize || lineWidth != self.lineWidth
        guard changed else { return }
        self.fraction = clamped
        self.playing = playing
        self.knobSize = knobSize
        self.lineWidth = lineWidth
        self.duration = Double(durationMs) / 1000
        self.remaining = duration * (1 - clamped)
        anchorTime = CACurrentMediaTime()
        restart()
    }

    func receive(_ levels: [Float]) {
        guard playing, !grabbed, let first = levels.first, window?.occlusionState.contains(.visible) == true else { return }
        let target = CGFloat(first)
        bass += (target - bass) * (target > bass ? 0.7 : 0.18)
        lastBeat = Date()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.09)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        let swell = 1 + bass * 0.45
        drop.transform = CATransform3DMakeScale(swell, swell, 1)
        drop.shadowOpacity = Float(0.25 + bass * 0.65)
        drop.shadowRadius = 5 + bass * 8
        fill.transform = CATransform3DMakeScale(1 + bass * 0.5, 1, 1)
        CATransaction.commit()
        scheduleSettle()
    }

    private func scheduleSettle() {
        relaxWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.grabbed, Date().timeIntervalSince(self.lastBeat) > 0.3 else { return }
            self.bass = 0
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.4)
            self.drop.transform = CATransform3DIdentity
            self.drop.shadowOpacity = 0.3
            self.drop.shadowRadius = 6
            self.fill.transform = CATransform3DIdentity
            CATransaction.commit()
        }
        relaxWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func drag(to target: Double) {
        let y = self.y(for: min(max(target, 0), 1)) + knobSize / 2
        let now = CACurrentMediaTime()
        if !grabbed {
            grabbed = true
            relaxWork?.cancel()
            knob.removeAllAnimations()
            fill.removeAllAnimations()
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.16)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.3, 1.6, 0.5, 1))
            drop.transform = CATransform3DMakeScale(1.35, 1.35, 1)
            drop.shadowOpacity = 0.8
            drop.shadowRadius = 12
            fill.transform = CATransform3DMakeScale(1.3, 1, 1)
            CATransaction.commit()
        }
        var stretch: CGFloat = 0
        if let last = lastDrag, now > last.time {
            let speed = abs(y - last.y) / CGFloat(now - last.time)
            stretch = min(speed / 900, 1)
        }
        lastDrag = (y, now)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        knob.position = CGPoint(x: bounds.midX, y: y)
        fill.bounds = CGRect(x: 0, y: 0, width: lineWidth, height: y)
        CATransaction.commit()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.07)
        drop.transform = CATransform3DMakeScale(1.35 * (1 - stretch * 0.32), 1.35 * (1 + stretch * 0.9), 1)
        CATransaction.commit()

        relaxWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.grabbed else { return }
            self.lastDrag = nil
            self.spring(self.drop, to: CATransform3DMakeScale(1.35, 1.35, 1))
        }
        relaxWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func release() {
        grabbed = false
        lastDrag = nil
        relaxWork?.cancel()
        spring(drop, to: CATransform3DIdentity)
        spring(fill, to: CATransform3DIdentity)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        drop.shadowOpacity = 0.3
        drop.shadowRadius = 6
        CATransaction.commit()
    }

    private func spring(_ layer: CALayer, to transform: CATransform3D) {
        let from = layer.presentation()?.transform ?? layer.transform
        let animation = CASpringAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: from)
        animation.toValue = NSValue(caTransform3D: transform)
        animation.mass = 0.6
        animation.stiffness = 320
        animation.damping = 7
        animation.duration = animation.settlingDuration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = transform
        CATransaction.commit()
        layer.add(animation, forKey: "spring")
    }

    private func currentFraction() -> Double {
        guard playing, remaining > 0 else { return fraction }
        let elapsed = CACurrentMediaTime() - anchorTime
        return min(1, fraction + (1 - fraction) * elapsed / remaining)
    }

    private func y(for fraction: Double) -> CGFloat {
        (bounds.height - knobSize) * CGFloat(fraction)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = bounds
        let path = CGMutablePath()
        path.move(to: CGPoint(x: bounds.midX, y: 1))
        path.addLine(to: CGPoint(x: bounds.midX, y: bounds.height - 1))
        track.path = path
        CATransaction.commit()
        guard !grabbed else { return }
        fraction = currentFraction()
        remaining = duration * (1 - fraction)
        anchorTime = CACurrentMediaTime()
        restart()
    }

    private func restart() {
        let start = y(for: fraction) + knobSize / 2
        let end = y(for: 1) + knobSize / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        knob.removeAnimation(forKey: "progress")
        fill.removeAnimation(forKey: "progress")
        knob.bounds = CGRect(x: 0, y: 0, width: knobSize, height: knobSize)
        drop.bounds = knob.bounds
        drop.position = CGPoint(x: knobSize / 2, y: knobSize / 2)
        drop.cornerRadius = knobSize / 2
        drop.shadowPath = CGPath(ellipseIn: drop.bounds, transform: nil)
        knob.position = CGPoint(x: bounds.midX, y: start)
        fill.bounds = CGRect(x: 0, y: 0, width: lineWidth, height: start)
        fill.cornerRadius = lineWidth / 2
        fill.position = CGPoint(x: bounds.midX, y: 0)
        CATransaction.commit()

        guard playing, remaining > 0.05 else { return }
        let move = CABasicAnimation(keyPath: "position.y")
        move.fromValue = start
        move.toValue = end
        move.duration = remaining
        move.fillMode = .forwards
        move.isRemovedOnCompletion = false
        knob.add(move, forKey: "progress")

        let grow = CABasicAnimation(keyPath: "bounds.size.height")
        grow.fromValue = start
        grow.toValue = end
        grow.duration = remaining
        grow.fillMode = .forwards
        grow.isRemovedOnCompletion = false
        fill.add(grow, forKey: "progress")
    }
}

struct RailLayer: NSViewRepresentable {
    let player: Player
    let fraction: Double
    let playing: Bool
    let durationMs: Int
    let color: NSColor
    let dragging: Double?
    let knobSize: CGFloat
    let lineWidth: CGFloat
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
        view.apply(fraction: fraction, playing: playing, durationMs: durationMs, color: color,
                   dragging: dragging, knobSize: knobSize, lineWidth: lineWidth)
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

            RailLayer(player: player, fraction: live, playing: player.isPlaying, durationMs: player.durationMs,
                      color: player.accent, dragging: dragFraction.map { min(max($0, 0), 1) },
                      knobSize: knob, lineWidth: hovering ? 6 : 5,
                      showTime: hovering && dragFraction == nil)
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
                        .offset(x: geo.size.width / 2 + knob / 2 + 12, y: y - 2)
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
