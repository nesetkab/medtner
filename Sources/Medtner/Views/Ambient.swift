import AppKit
import QuartzCore
import SwiftUI

final class RippleView: NSView {
    private let rings: [CAShapeLayer] = (0..<3).map { _ in CAShapeLayer() }
    private var active = false
    private var cover: CGFloat = 0
    private var radius: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for ring in rings {
            ring.fillColor = nil
            ring.lineWidth = 1.5
            ring.opacity = 0
            layer?.addSublayer(ring)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(color: NSColor, active: Bool, cover: CGFloat, radius: CGFloat) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.9)
        for ring in rings { ring.strokeColor = color.cgColor }
        CATransaction.commit()
        let sizeChanged = cover != self.cover || radius != self.radius
        self.cover = cover
        self.radius = radius
        if sizeChanged { needsLayout = true }
        guard active != self.active else { return }
        self.active = active
        active ? start() : stop()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let rect = CGRect(x: (bounds.width - cover) / 2, y: (bounds.height - cover) / 2, width: cover, height: cover)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        for ring in rings {
            ring.frame = bounds
            ring.path = path
        }
        CATransaction.commit()
        if active { start() }
    }

    private func start() {
        let now = CACurrentMediaTime()
        for (i, ring) in rings.enumerated() {
            ring.removeAllAnimations()
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 1.0
            grow.toValue = 1.22
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.55, 0]
            fade.keyTimes = [0, 0.15, 1]
            let group = CAAnimationGroup()
            group.animations = [grow, fade]
            group.duration = 4.2
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.6, 0.3, 1)
            group.beginTime = now + Double(i) * 1.4
            group.fillMode = .backwards
            ring.add(group, forKey: "ripple")
        }
    }

    private func stop() {
        for ring in rings {
            let current = ring.presentation()?.opacity ?? 0
            ring.removeAllAnimations()
            ring.opacity = current
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = current
            fade.toValue = 0
            fade.duration = 0.6
            ring.add(fade, forKey: "out")
            ring.opacity = 0
        }
    }
}

struct AmbientRipples: NSViewRepresentable {
    let color: NSColor
    let active: Bool
    let size: CGFloat
    let radius: CGFloat

    func makeNSView(context: Context) -> RippleView { RippleView(frame: .zero) }

    func updateNSView(_ view: RippleView, context: Context) {
        view.update(color: color, active: active, cover: size, radius: radius)
    }
}
