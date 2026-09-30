import AppKit
import QuartzCore
import SwiftUI

final class BlobView: NSView {
    private let container = CALayer()
    private let blobs: [CAGradientLayer] = (0..<5).map { _ in CAGradientLayer() }
    private var smoothed: [CGFloat] = [0, 0, 0, 0, 0]
    private var playing = false
    private var started = false
    private var reactive = false
    private var lastLevels = Date.distantPast
    private var colors: [NSColor] = []
    private var diameter: CGFloat = 0
    private var watchdog: Timer?
    var spread: CGFloat = 1
    var glow: Float = 1

    private let anchors: [CGPoint] = [
        CGPoint(x: -0.26, y: -0.24),
        CGPoint(x: 0.3, y: 0.26),
        CGPoint(x: 0.28, y: -0.3),
        CGPoint(x: -0.3, y: 0.3),
        CGPoint(x: 0.02, y: 0.02),
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(container)
        for blob in blobs.reversed() {
            blob.type = .radial
            blob.startPoint = CGPoint(x: 0.5, y: 0.5)
            blob.endPoint = CGPoint(x: 1, y: 1)
            blob.locations = [0, 0.18, 0.38, 0.58, 0.78, 1]
            blob.contentsScale = 0.75
            blob.opacity = 0
            container.addSublayer(blob)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(colors: [NSColor], playing: Bool, diameter: CGFloat) {
        if colors != self.colors {
            self.colors = colors
            CATransaction.begin()
            CATransaction.setAnimationDuration(1.2)
            for (i, blob) in blobs.enumerated() {
                let color = i == 4 ? (colors.first ?? .white) : colors[i % max(colors.count, 1)]
                blob.colors = [0.85, 0.7, 0.45, 0.22, 0.07, 0].map { color.withAlphaComponent($0).cgColor }
            }
            CATransaction.commit()
        }
        if diameter != self.diameter {
            self.diameter = diameter
            needsLayout = true
        }
        guard playing != self.playing || !started else { return }
        started = true
        self.playing = playing
        playing ? begin() : rest()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for (i, blob) in blobs.enumerated() {
            let size = diameter * [1.05, 0.85, 0.85, 0.85, 0.95][i]
            blob.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            blob.position = CGPoint(x: center.x + anchors[i].x * diameter * spread, y: center.y + anchors[i].y * diameter * spread)
        }
        CATransaction.commit()
    }

    func receive(_ levels: [Float]) {
        guard playing, window?.occlusionState.contains(.visible) == true else { return }
        lastLevels = Date()
        if !reactive {
            reactive = true
            for blob in blobs { blob.removeAnimation(forKey: "idle") }
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.09)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        let overall = levels.reduce(0, +) / Float(max(levels.count, 1))
        for (i, blob) in blobs.enumerated() {
            let target = CGFloat(i < levels.count ? levels[i] : overall)
            let rate: CGFloat = target > smoothed[i] ? 0.55 : 0.14
            smoothed[i] += (target - smoothed[i]) * rate
            let scale = 0.7 + smoothed[i] * 0.55
            blob.transform = CATransform3DMakeScale(scale, scale, 1)
            blob.opacity = min(1, Float(0.3 + smoothed[i] * 0.5) * glow)
        }
        CATransaction.commit()
    }

    private func begin() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.8)
        for blob in blobs { blob.opacity = min(1, 0.45 * glow) }
        CATransaction.commit()

        let drift = CABasicAnimation(keyPath: "transform.rotation.z")
        drift.fromValue = 0
        drift.toValue = Double.pi * 2
        drift.duration = 48
        drift.repeatCount = .infinity
        container.add(drift, forKey: "drift")

        reactive = false
        startIdlePulse(calm: false)
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.reactive, Date().timeIntervalSince(self.lastLevels) > 0.6 else { return }
            self.reactive = false
            self.startIdlePulse(calm: false)
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func startIdlePulse(calm: Bool) {
        for (i, blob) in blobs.enumerated() {
            blob.transform = CATransform3DMakeScale(0.85, 0.85, 1)
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = calm ? 0.82 : 0.72
            pulse.toValue = calm ? [0.98, 0.92, 1.0, 0.9, 0.95][i] : [1.08, 0.95, 1.12, 0.9, 1.0][i]
            pulse.duration = (calm ? 3.2 : 1) * [0.9, 1.3, 1.1, 1.6, 2.1][i]
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.timeOffset = Double(i) * 0.37
            blob.add(pulse, forKey: "idle")
        }
    }

    private func rest() {
        watchdog?.invalidate()
        watchdog = nil
        reactive = false
        if container.animation(forKey: "drift") == nil {
            let drift = CABasicAnimation(keyPath: "transform.rotation.z")
            drift.fromValue = 0
            drift.toValue = Double.pi * 2
            drift.duration = 48
            drift.repeatCount = .infinity
            container.add(drift, forKey: "drift")
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(1.2)
        for (i, blob) in blobs.enumerated() {
            blob.opacity = min(1, 0.36 * glow)
            smoothed[i] = 0
        }
        CATransaction.commit()
        startIdlePulse(calm: true)
    }
}

struct AmbientBlobs: NSViewRepresentable {
    let player: Player
    let colors: [NSColor]
    let playing: Bool
    let diameter: CGFloat
    var spread: CGFloat = 1
    var glow: Float = 1

    func makeNSView(context: Context) -> BlobView {
        let view = BlobView(frame: .zero)
        view.spread = spread
        view.glow = glow
        player.engine.audio.onLevels = { [weak view] levels in
            DispatchQueue.main.async { view?.receive(levels) }
        }
        return view
    }

    func updateNSView(_ view: BlobView, context: Context) {
        view.update(colors: colors, playing: playing, diameter: diameter)
    }
}
