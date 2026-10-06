import SwiftUI

struct LyricsPanel: View {
    @Bindable var player: Player
    let lyrics: Lyrics

    var body: some View {
        Group {
            if lyrics.synced {
                synced
            } else {
                plain
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.14),
                .init(color: .black, location: 0.78),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
    }

    private var synced: some View {
        let index = player.lyricIndex ?? -1
        let lower = max(0, index - 2)
        let upper = min(lyrics.lines.count - 1, max(index, 0) + 6)
        return VStack(alignment: .leading, spacing: 14) {
            if lower <= upper {
                ForEach(lyrics.lines[lower...upper]) { line in
                    LyricRow(line: line, place: place(of: line, current: index), synced: true, accent: player.accentColor) {
                        player.seek(toMs: line.time)
                    }
                    .transition(.asymmetric(
                        insertion: .offset(y: 30).combined(with: .opacity),
                        removal: .offset(y: -30).combined(with: .opacity)
                    ))
                }
            }
        }
        .padding(.top, index < 2 ? CGFloat(2 - max(index, 0)) * 44 + 24 : 24)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .animation(.spring(response: 0.75, dampingFraction: 0.9), value: index)
    }

    private var plain: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                Color.clear.frame(height: 40)
                ForEach(lyrics.lines) { line in
                    LyricRow(line: line, place: .plain, synced: false, accent: player.accentColor) {}
                }
                Color.clear.frame(height: 120)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func place(of line: LyricLine, current: Int) -> LyricRow.Place {
        if line.id == current { return .current }
        return line.id < current ? .past : .upcoming
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
            .scaleEffect(place == .current ? 1 : 0.95, anchor: .leading)
            .blur(radius: place == .current || place == .plain || hovering ? 0 : 0.6)
            .animation(.spring(response: 0.75, dampingFraction: 0.9), value: place)
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
