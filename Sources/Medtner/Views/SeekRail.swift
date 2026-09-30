import AppKit
import QuartzCore
import SwiftUI

final class RailLayerView: NSView {
    private let fill = CALayer()
    private let knob = CALayer()
    private let bubble = CALayer()
    private let label = CATextLayer()
    private var bubbleTimer: Timer?
    private var showingTime = false
    private var fraction: Double = 0
    private var playing = false
    private var remaining: Double = 0
    private var duration: Double = 0
    private var anchorTime = CACurrentMediaTime()
    private var knobSize: CGFloat = 15
    private var lineWidth: CGFloat = 3

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        fill.anchorPoint = CGPoint(x: 0.5, y: 0)
        knob.cornerRadius = 4
        knob.cornerCurve = .continuous
        knob.shadowOpacity = 0.35
        knob.shadowRadius = 4
        knob.shadowOffset = .zero
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

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        label.contentsScale = scale
    }

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

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(fraction: Double, playing: Bool, durationMs: Int, color: NSColor, hidden: Bool, knobSize: CGFloat, lineWidth: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.backgroundColor = color.withAlphaComponent(0.35).cgColor
        knob.backgroundColor = color.cgColor
        knob.shadowColor = color.cgColor
        bubble.backgroundColor = color.cgColor
        knob.opacity = hidden ? 0 : 1
        fill.opacity = hidden ? 0 : 1
        CATransaction.commit()

        let clamped = min(max(fraction, 0), 1)
        let expected = currentFraction()
        let drift = abs(expected - clamped) * Double(durationMs) / 1000
        let changed = playing != self.playing || drift > 0.6 || knobSize != self.knobSize || lineWidth != self.lineWidth
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
        fraction = currentFraction()
        remaining = duration * (1 - fraction)
        anchorTime = CACurrentMediaTime()
        restart()
    }

    private func restart() {
        let start = y(for: fraction)
        let end = y(for: 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        knob.removeAllAnimations()
        fill.removeAllAnimations()
        knob.bounds = CGRect(x: 0, y: 0, width: knobSize, height: knobSize)
        knob.shadowPath = CGPath(roundedRect: knob.bounds, cornerWidth: 4, cornerHeight: 4, transform: nil)
        knob.position = CGPoint(x: bounds.midX, y: start + knobSize / 2)
        fill.bounds = CGRect(x: 0, y: 0, width: lineWidth, height: start + knobSize / 2)
        fill.position = CGPoint(x: bounds.midX, y: 0)
        CATransaction.commit()

        guard playing, remaining > 0.05 else { return }
        let move = CABasicAnimation(keyPath: "position.y")
        move.fromValue = start + knobSize / 2
        move.toValue = end + knobSize / 2
        move.duration = remaining
        move.fillMode = .forwards
        move.isRemovedOnCompletion = false
        knob.add(move, forKey: "progress")

        let grow = CABasicAnimation(keyPath: "bounds.size.height")
        grow.fromValue = start + knobSize / 2
        grow.toValue = end + knobSize / 2
        grow.duration = remaining
        grow.fillMode = .forwards
        grow.isRemovedOnCompletion = false
        fill.add(grow, forKey: "progress")
    }
}

struct RailLayer: NSViewRepresentable {
    let fraction: Double
    let playing: Bool
    let durationMs: Int
    let color: NSColor
    let hidden: Bool
    let knobSize: CGFloat
    let lineWidth: CGFloat
    let showTime: Bool

    func makeNSView(context: Context) -> RailLayerView { RailLayerView(frame: .zero) }

    func updateNSView(_ view: RailLayerView, context: Context) {
        view.apply(fraction: fraction, playing: playing, durationMs: durationMs, color: color,
                   hidden: hidden, knobSize: knobSize, lineWidth: lineWidth)
        view.showTime(showTime)
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
                    .fill(Color(white: 0.55))
                    .frame(width: hovering ? 4 : 3)
                    .frame(maxHeight: .infinity)

                RailLayer(fraction: live, playing: player.isPlaying, durationMs: player.durationMs,
                          color: player.accent, hidden: dragFraction != nil,
                          knobSize: knob, lineWidth: hovering ? 4 : 3,
                          showTime: hovering && dragFraction == nil)

                if let dragFraction {
                    let y = travel * CGFloat(min(max(dragFraction, 0), 1))
                    Capsule()
                        .fill(player.accentColor.opacity(0.35))
                        .frame(width: 4, height: y + 9)
                        .frame(maxHeight: .infinity, alignment: .top)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(player.accentColor)
                        .frame(width: 18, height: 18)
                        .shadow(color: player.accentColor.opacity(0.8), radius: 10)
                        .offset(y: y - 1.5)
                }

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
                        .offset(x: geo.size.width / 2 + knob / 2 + 8, y: y - 2)
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
