import SwiftUI

struct LyricsPanel: View {
    @Bindable var player: Player
    let lyrics: Lyrics

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: lyrics.synced ? 14 : 8) {
                    Color.clear.frame(height: 70)
                    ForEach(lyrics.lines) { line in
                        LyricRow(line: line, place: place(of: line), synced: lyrics.synced, accent: player.accentColor) {
                            player.seek(toMs: line.time)
                        }
                        .id(line.id)
                    }
                    Color.clear.frame(height: 180)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { center(proxy, animated: false) }
            .onChange(of: player.lyricIndex) { _, _ in center(proxy, animated: true) }
        }
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.16),
                .init(color: .black, location: 0.78),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
    }

    private func place(of line: LyricLine) -> LyricRow.Place {
        guard lyrics.synced, let index = player.lyricIndex else { return lyrics.synced ? .upcoming : .plain }
        if line.id == index { return .current }
        return line.id < index ? .past : .upcoming
    }

    private func center(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let index = player.lyricIndex else { return }
        if animated {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.88)) {
                proxy.scrollTo(index, anchor: UnitPoint(x: 0, y: 0.32))
            }
        } else {
            proxy.scrollTo(index, anchor: UnitPoint(x: 0, y: 0.32))
        }
    }
}

struct LyricRow: View {
    enum Place { case past, current, upcoming, plain }

    let line: LyricLine
    let place: Place
    let synced: Bool
    let accent: Color
    let seek: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(line.text.isEmpty ? "· · ·" : line.text)
            .font(.system(size: synced ? 20 : 15, weight: synced ? .bold : .medium))
            .tracking(synced ? -0.5 : -0.2)
            .lineSpacing(2)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .scaleEffect(place == .current ? 1 : 0.97, anchor: .leading)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: place)
            .contentShape(Rectangle())
            .onHover { hovering = $0 && synced }
            .pointerStyle(synced ? .link : .default)
            .onTapGesture { if synced { seek() } }
    }

    private var color: Color {
        if hovering && place != .current { return .white.opacity(0.75) }
        switch place {
        case .current: return .white
        case .past: return .white.opacity(0.26)
        case .upcoming: return .white.opacity(0.4)
        case .plain: return .white.opacity(0.75)
        }
    }
}

struct LyricsStrip: View {
    @Bindable var player: Player
    let lyrics: Lyrics
    let size: CGFloat

    var body: some View {
        let index = player.lyricIndex ?? -1
        let lower = max(0, index - 1)
        let upper = min(lyrics.lines.count - 1, max(index, 0) + 2)
        VStack(alignment: .leading, spacing: size * 0.38) {
            if lower <= upper {
                ForEach(lyrics.lines[lower...upper]) { line in
                    let current = line.id == index
                    Text(line.text.isEmpty ? "· · ·" : line.text)
                        .font(.system(size: size, weight: .bold))
                        .tracking(-size * 0.03)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.white.opacity(current ? 1 : line.id < index ? 0.22 : 0.34))
                        .scaleEffect(current ? 1 : 0.9, anchor: .leading)
                        .blur(radius: current ? 0 : 1.5)
                        .transition(.asymmetric(
                            insertion: .offset(y: size * 1.2).combined(with: .opacity),
                            removal: .offset(y: -size * 1.2).combined(with: .opacity)
                        ))
                }
            }
        }
        .frame(minHeight: size * 6.2, alignment: .bottom)
        .animation(.spring(response: 0.75, dampingFraction: 0.9), value: index)
    }
}

struct LyricsToggle: View {
    @Binding var on: Bool
    let available: Bool
    let accent: Color

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { on.toggle() }
        } label: {
            Image(systemName: "quote.bubble")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(on && available ? accent : Color(white: on ? 0.55 : 0.4))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(PressStyle())
        .help(available ? (on ? "Hide lyrics" : "Show lyrics") : "No lyrics for this song")
    }
}
