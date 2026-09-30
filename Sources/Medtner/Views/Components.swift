import SwiftUI

struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.82

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle().inset(by: -8))
            .pointerStyle(.link)
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

struct HoverLift: ViewModifier {
    var amount: CGFloat = 1.06
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? amount : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverLift(_ amount: CGFloat = 1.06) -> some View { modifier(HoverLift(amount: amount)) }
}

struct Magnifier: View {
    var lineWidth: CGFloat = 2.4

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let r = s * 0.3
            let center = CGPoint(x: s * 0.6, y: s * 0.4)
            let ring = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            context.stroke(ring, with: .foreground, lineWidth: lineWidth)
            var handle = Path()
            let angle = CGFloat.pi * 0.75
            handle.move(to: CGPoint(x: center.x + cos(angle) * (r + lineWidth / 2), y: center.y + sin(angle) * (r + lineWidth / 2)))
            handle.addLine(to: CGPoint(x: center.x + cos(angle) * s * 0.62, y: center.y + sin(angle) * s * 0.62))
            context.stroke(handle, with: .foreground, style: StrokeStyle(lineWidth: lineWidth * 1.15, lineCap: .round))
        }
    }
}

struct PlayPauseShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        if progress < 0.02 {
            var triangle = Path()
            triangle.move(to: CGPoint(x: rect.minX + 0.08 * w, y: rect.minY))
            triangle.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            triangle.addLine(to: CGPoint(x: rect.minX + 0.08 * w, y: rect.maxY))
            triangle.closeSubpath()
            return triangle
        }
        func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + (a.x + (b.x - a.x) * progress) * w, y: rect.minY + (a.y + (b.y - a.y) * progress) * h)
        }
        let left = [
            mix(CGPoint(x: 0.08, y: 0), CGPoint(x: 0.12, y: 0.02)),
            mix(CGPoint(x: 0.54, y: 0.26), CGPoint(x: 0.38, y: 0.02)),
            mix(CGPoint(x: 0.54, y: 0.74), CGPoint(x: 0.38, y: 0.98)),
            mix(CGPoint(x: 0.08, y: 1), CGPoint(x: 0.12, y: 0.98)),
        ]
        let right = [
            mix(CGPoint(x: 0.54, y: 0.26), CGPoint(x: 0.62, y: 0.02)),
            mix(CGPoint(x: 1, y: 0.5), CGPoint(x: 0.88, y: 0.02)),
            mix(CGPoint(x: 1, y: 0.5), CGPoint(x: 0.88, y: 0.98)),
            mix(CGPoint(x: 0.54, y: 0.74), CGPoint(x: 0.62, y: 0.98)),
        ]
        var path = Path()
        path.addLines(left)
        path.closeSubpath()
        path.addLines(right)
        path.closeSubpath()
        return path
    }
}

struct SkipShape: Shape {
    var forward = true

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0.04 * w, y: 0.06 * h))
        path.addLine(to: CGPoint(x: 0.7 * w, y: 0.5 * h))
        path.addLine(to: CGPoint(x: 0.04 * w, y: 0.94 * h))
        path.closeSubpath()
        path.addRect(CGRect(x: 0.84 * w, y: 0.06 * h, width: 0.12 * w, height: 0.88 * h))
        guard !forward else { return path.offsetBy(dx: rect.minX, dy: rect.minY) }
        return path
            .applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -w, y: 0))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

struct Soft<S: Shape>: View {
    let shape: S
    var corner: CGFloat = 2

    var body: some View {
        shape
            .fill(.foreground)
            .overlay(shape.stroke(.foreground, style: StrokeStyle(lineWidth: corner, lineJoin: .round)))
    }
}

struct Transport: View {
    @Bindable var player: Player
    var size: CGFloat = 18
    var spacing: CGFloat = 24

    var body: some View {
        HStack(spacing: spacing) {
            Button { player.previous() } label: {
                Soft(shape: SkipShape(forward: false), corner: size * 0.08)
                    .frame(width: size * 0.95, height: size * 0.9)
            }
            Button { player.togglePlay() } label: {
                Soft(shape: PlayPauseShape(progress: player.isPlaying ? 1 : 0), corner: size * 0.09)
                    .frame(width: size * 0.9, height: size)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: player.isPlaying)
            }
            Button { player.next() } label: {
                Soft(shape: SkipShape(forward: true), corner: size * 0.08)
                    .frame(width: size * 0.95, height: size * 0.9)
            }
        }
        .frame(height: size)
        .buttonStyle(PressStyle())
        .foregroundStyle(.white)
    }
}

struct VolumeBar: View {
    @Bindable var player: Player
    var width: CGFloat = 140
    @State private var dragging = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                player.setVolume(player.volume > 0 ? 0 : 60)
            } label: {
                Image(systemName: "speaker.wave.3.fill", variableValue: Double(player.volume) / 100)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 24, height: 18, alignment: .leading)
                    .contentTransition(.symbolEffect(.automatic))
            }
            .buttonStyle(PressStyle())

            GeometryReader { geo in
                let fraction = CGFloat(player.volume) / 100
                let thick: CGFloat = dragging || hovering ? 8 : 6
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.3)).frame(height: thick)
                    Capsule().fill(.white)
                        .frame(width: max(thick, geo.size.width * fraction), height: thick)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .pointerStyle(.link)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragging = true
                            player.setVolume(Int((value.location.x / geo.size.width) * 100))
                        }
                        .onEnded { _ in dragging = false }
                )
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: thick)
            }
            .frame(width: width, height: 20)
            .onHover { hovering = $0 }
        }
        .foregroundStyle(.white)
    }
}

func formatTime(_ ms: Int) -> String {
    let total = max(ms, 0) / 1000
    return String(format: "%d:%02d", total / 60, total % 60)
}
