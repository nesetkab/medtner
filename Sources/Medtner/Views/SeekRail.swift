import AppKit
import QuartzCore
import SwiftUI

final class RailLayerView: NSView {
    private let fill = CALayer()
    private let knob = CALayer()
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
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(fraction: Double, playing: Bool, durationMs: Int, color: NSColor, hidden: Bool, knobSize: CGFloat, lineWidth: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.backgroundColor = color.withAlphaComponent(0.35).cgColor
        knob.backgroundColor = color.cgColor
        knob.shadowColor = color.cgColor
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

    func makeNSView(context: Context) -> RailLayerView { RailLayerView(frame: .zero) }

    func updateNSView(_ view: RailLayerView, context: Context) {
        view.apply(fraction: fraction, playing: playing, durationMs: durationMs, color: color,
                   hidden: hidden, knobSize: knobSize, lineWidth: lineWidth)
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
            let shown = dragFraction ?? live

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color(white: 0.55))
                    .frame(width: hovering ? 4 : 3)
                    .frame(maxHeight: .infinity)

                RailLayer(fraction: live, playing: player.isPlaying, durationMs: player.durationMs,
                          color: player.accent, hidden: dragFraction != nil,
                          knobSize: knob, lineWidth: hovering ? 4 : 3)

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

                if hovering || dragFraction != nil {
                    let y = travel * CGFloat(min(max(shown, 0), 1))
                    Text(formatTime(Int(Double(player.durationMs) * shown)))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(player.accentColor))
                        .fixedSize()
                        .offset(x: knob + 14, y: y - 2)
                        .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
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
