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
        VStack(alignment: .leading, spacing: size * 0.35) {
            line(at: index - 1, opacity: 0.3, scale: 0.62)
            line(at: index, opacity: 1, scale: 1)
            line(at: index + 1, opacity: 0.38, scale: 0.62)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: index)
    }

    @ViewBuilder
    private func line(at index: Int, opacity: Double, scale: CGFloat) -> some View {
        let text = lyrics.lines.indices.contains(index) ? lyrics.lines[index].text : ""
        Text(text.isEmpty ? " " : text)
            .font(.system(size: size * scale, weight: .bold))
            .tracking(-size * scale * 0.03)
            .lineLimit(2)
            .foregroundStyle(.white.opacity(opacity))
            .id("\(index)-\(opacity)")
            .transition(.asymmetric(
                insertion: .offset(y: size * 0.6).combined(with: .opacity),
                removal: .offset(y: -size * 0.6).combined(with: .opacity)
            ))
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
