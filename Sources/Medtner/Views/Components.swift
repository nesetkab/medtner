import SwiftUI

struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.82
    var hover: CGFloat = 1.14

    func makeBody(configuration: Configuration) -> some View {
        PressBody(label: configuration.label, pressed: configuration.isPressed, scale: scale, hover: hover)
    }
}

private struct PressBody<Label: View>: View {
    let label: Label
    let pressed: Bool
    let scale: CGFloat
    let hover: CGFloat
    @State private var hovering = false

    var body: some View {
        label
            .scaleEffect(pressed ? scale : hovering ? hover : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: pressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hovering)
            .padding(10)
            .contentShape(Rectangle())
            .padding(-10)
            .pointerStyle(.link)
            .onHover { hovering = $0 }
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
    var extras = false

    var body: some View {
        HStack(spacing: spacing) {
            if extras {
                Button { player.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: size * 0.8, weight: .semibold))
                        .foregroundStyle(player.shuffle ? player.accentColor : Palette.muted)
                        .overlay(alignment: .bottom) {
                            Circle()
                                .fill(player.accentColor)
                                .frame(width: 4, height: 4)
                                .offset(y: 8)
                                .opacity(player.shuffle ? 1 : 0)
                        }
                        .frame(height: size)
                }
                .help("Shuffle")
            }
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
            if extras {
                LikeButton(player: player, size: size)
            }
        }
        .frame(height: size)
        .buttonStyle(PressStyle())
        .foregroundStyle(.white)
    }
}

struct LikeButton: View {
    @Bindable var player: Player
    let size: CGFloat
    @State private var picking = false
    @State private var burst = false

    var body: some View {
        Button {
            guard let uri = player.track?.uri else { return }
            if player.liked {
                picking = true
            } else {
                player.like(uri)
                burst.toggle()
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Palette.muted, lineWidth: 1.6)
                    .opacity(player.liked ? 0 : 1)
                Image(systemName: "plus")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .opacity(player.liked ? 0 : 1)
                    .rotationEffect(.degrees(player.liked ? 90 : 0))
                Circle()
                    .fill(player.accentColor)
                    .scaleEffect(player.liked ? 1 : 0.2)
                    .opacity(player.liked ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.46, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.8))
                    .scaleEffect(player.liked ? 1 : 0.3)
                    .opacity(player.liked ? 1 : 0)
            }
            .frame(width: size, height: size)
            .symbolEffect(.bounce, value: burst)
            .animation(.spring(response: 0.35, dampingFraction: 0.55), value: player.liked)
        }
        .help(player.liked ? "Add to playlist" : "Save to Liked Songs")
        .popover(isPresented: $picking, arrowEdge: .top) {
            PlaylistPicker(player: player) { picking = false }
        }
    }
}

struct PlaylistPicker: View {
    @Bindable var player: Player
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Add to playlist")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            PickerRow(title: "Liked Songs", checked: true, accent: player.accentColor) {
                if let uri = player.track?.uri { player.unlike(uri) }
                done()
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(player.editable) { list in
                        PickerRow(title: list.title, checked: false, accent: player.accentColor) {
                            if let uri = player.track?.uri { player.add(uri, to: list) }
                            done()
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(8)
        .frame(width: 230)
        .background(Palette.background)
        .foregroundStyle(.white)
    }
}

struct PickerRow: View {
    let title: String
    let checked: Bool
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: checked ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(checked ? accent : Palette.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Color(white: 0.17) : .clear))
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hovering)
        .contentShape(Rectangle())
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
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
