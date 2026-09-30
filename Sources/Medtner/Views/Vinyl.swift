import AppKit
import QuartzCore
import SwiftUI

enum RecordArt {
    static func render(label: NSImage?, size: CGFloat, accent: NSColor) -> NSImage {
        let scale: CGFloat = 2
        let px = Int(size * scale)
        let image = NSImage(size: NSSize(width: size, height: size))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return image }
        rep.size = NSSize(width: size, height: size)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let center = CGPoint(x: size / 2, y: size / 2)
        ctx.setFillColor(NSColor(white: 0.04, alpha: 1).cgColor)
        ctx.fillEllipse(in: rect)

        var radius = size / 2 - 3
        var toggle = false
        while radius > size * 0.22 {
            ctx.setStrokeColor(NSColor(white: toggle ? 0.13 : 0.09, alpha: 1).cgColor)
            ctx.setLineWidth(0.6)
            ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            radius -= CGFloat.random(in: 1.4...2.6)
            toggle.toggle()
        }

        for (start, alpha) in [(CGFloat.pi * 0.15, 0.10), (CGFloat.pi * 1.15, 0.07)] {
            ctx.saveGState()
            ctx.move(to: center)
            ctx.addArc(center: center, radius: size / 2 - 2, startAngle: start, endAngle: start + .pi * 0.28, clockwise: false)
            ctx.closePath()
            ctx.clip()
            ctx.setFillColor(NSColor(white: 1, alpha: alpha).cgColor)
            ctx.fillEllipse(in: rect.insetBy(dx: 2, dy: 2))
            ctx.restoreGState()
        }

        let labelRadius = size * 0.2
        let labelRect = CGRect(x: center.x - labelRadius, y: center.y - labelRadius, width: labelRadius * 2, height: labelRadius * 2)
        ctx.saveGState()
        ctx.addEllipse(in: labelRect)
        ctx.clip()
        if let cg = label?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.draw(cg, in: labelRect)
        } else {
            ctx.setFillColor(accent.cgColor)
            ctx.fill(labelRect)
        }
        ctx.restoreGState()

        ctx.setFillColor(NSColor(white: 0.06, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
        NSGraphicsContext.restoreGraphicsState()

        image.addRepresentation(rep)
        return image
    }
}

final class SpinnerView: NSView {
    private let disc = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(disc)
        disc.contentsGravity = .resizeAspect
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -Double.pi * 2
        spin.duration = 1.8
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        disc.add(spin, forKey: "spin")
        disc.speed = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        disc.frame = bounds
        CATransaction.commit()
    }

    func update(image: NSImage?, spinning: Bool) {
        if let image, disc.contents as? NSImage !== image {
            disc.contents = image
        }
        let isSpinning = disc.speed != 0
        guard spinning != isSpinning else { return }
        if spinning {
            let paused = disc.timeOffset
            disc.speed = 1
            disc.timeOffset = 0
            disc.beginTime = 0
            disc.beginTime = disc.convertTime(CACurrentMediaTime(), from: nil) - paused
        } else {
            let paused = disc.convertTime(CACurrentMediaTime(), from: nil)
            disc.speed = 0
            disc.timeOffset = paused
        }
    }
}

struct SpinningRecord: NSViewRepresentable {
    let image: NSImage?
    let spinning: Bool

    func makeNSView(context: Context) -> SpinnerView { SpinnerView(frame: .zero) }

    func updateNSView(_ view: SpinnerView, context: Context) {
        view.update(image: image, spinning: spinning)
    }
}

struct Tonearm: View {
    let engaged: Bool
    let color: Color

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Color(white: 0.78))
                .frame(width: 5, height: 150)
                .offset(y: 8)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 16, height: 26)
                .offset(y: 150)
            Circle()
                .fill(Color(white: 0.2))
                .overlay(Circle().fill(Color(white: 0.78)).padding(7))
                .frame(width: 30, height: 30)
                .offset(y: -8)
        }
        .frame(width: 30, height: 190, alignment: .top)
        .rotationEffect(.degrees(engaged ? 24 : 2), anchor: UnitPoint(x: 0.5, y: 0.04))
        .animation(.spring(response: 0.9, dampingFraction: 0.65), value: engaged)
    }
}
