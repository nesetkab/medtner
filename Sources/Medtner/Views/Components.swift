import SwiftUI

struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.82

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
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
    var lineWidth: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let r = s * 0.3
            let center = CGPoint(x: s * 0.62, y: s * 0.36)
            let ring = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            context.stroke(ring, with: .foreground, lineWidth: lineWidth)
            var handle = Path()
            let start = CGPoint(x: center.x - r * 0.62, y: center.y + r * 0.8)
            handle.move(to: start)
            handle.addLine(to: CGPoint(x: s * 0.1, y: s * 0.95))
            context.stroke(handle, with: .foreground, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
        }
    }
}

struct Transport: View {
    @Bindable var player: Player
    var size: CGFloat = 30
    var spacing: CGFloat = 14

    var body: some View {
        HStack(spacing: spacing) {
            Button { player.previous() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: size, weight: .black))
            }
            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 1.05, weight: .black))
                    .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                    .frame(width: size * 1.25)
            }
            Button { player.next() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: size, weight: .black))
            }
        }
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
        HStack(spacing: 10) {
            Button {
                player.setVolume(player.volume > 0 ? 0 : 60)
            } label: {
                Image(systemName: "speaker.wave.3.fill", variableValue: Double(player.volume) / 100)
                    .font(.system(size: 24, weight: .black))
                    .frame(width: 34, alignment: .leading)
                    .contentTransition(.symbolEffect(.automatic))
            }
            .buttonStyle(PressStyle())

            GeometryReader { geo in
                let fraction = CGFloat(player.volume) / 100
                let thick: CGFloat = dragging || hovering ? 14 : 11
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.55)).frame(height: 2)
                    Capsule().fill(.white)
                        .frame(width: max(thick, geo.size.width * fraction), height: thick)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
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
