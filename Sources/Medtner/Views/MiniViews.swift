import SwiftUI

struct ThinProgress: View {
    @Bindable var player: Player
    var height: CGFloat = 4
    @State private var drag: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !player.isPlaying || drag != nil)) { timeline in
            GeometryReader { geo in
                let fraction = drag ?? player.fraction(at: timeline.date)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.25))
                    Capsule().fill(player.accentColor)
                        .frame(width: max(height, geo.size.width * fraction))
                        .animation(drag == nil ? .linear(duration: 1) : nil, value: fraction)
                }
                .frame(height: height)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag = min(max($0.location.x / geo.size.width, 0), 1) }
                        .onEnded {
                            player.seek(to: $0.location.x / geo.size.width)
                            drag = nil
                        }
                )
            }
        }
        .frame(height: 14)
    }
}

struct PillView: View {
    @Bindable var player: Player
    @State private var expanded = false

    var body: some View {
        VStack {
            content
                .background(
                    RoundedRectangle(cornerRadius: expanded ? 28 : 22, style: .continuous)
                        .fill(Color.black)
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                )
                .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .gesture(WindowDragGesture())
                .onHover { hover in
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { expanded = hover }
                }
            Spacer(minLength: 0)
        }
        .frame(width: 380, height: 150)
        .foregroundStyle(.white)
    }

    private var content: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Art(url: player.track?.artwork.best(near: 120), radius: expanded ? 10 : 7)
                    .frame(width: expanded ? 48 : 28, height: expanded ? 48 : 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(player.track?.name ?? "Medtner")
                        .font(.system(size: expanded ? 15 : 13, weight: .bold))
                        .lineLimit(1)
                    if expanded {
                        Text(player.track?.artistLine ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(white: 0.7))
                            .lineLimit(1)
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
                .id(player.track?.uri)
                .transition(.push(from: .bottom))
                Spacer(minLength: 6)
                if expanded {
                    Transport(player: player, size: 13, spacing: 16)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    EqualizerBars(playing: player.isPlaying, color: player.accentColor)
                        .frame(width: 16, height: 14)
                        .transition(.opacity)
                }
            }
            if expanded {
                ThinProgress(player: player, height: 3)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, expanded ? 16 : 10)
        .padding(.vertical, expanded ? 12 : 8)
        .frame(width: expanded ? 360 : 230)
    }
}
