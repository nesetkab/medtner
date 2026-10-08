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
        .clipShape(Rectangle())
        .contentShape(Rectangle())
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
        return AnchoredLines(lines: lyrics.lines, index: index, before: 2, after: 6, anchor: 0.3, spacing: 14) { line in
            LyricRow(line: line, place: place(of: line, current: index), synced: true, accent: player.accentColor) {
                player.seek(toMs: line.time)
            }
        }
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
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .rasterized(synced)
            .opacity(opacity)
            .scaleEffect(place == .current ? 1 : 0.95, anchor: .leading)
            .blur(radius: place == .current || place == .plain || hovering ? 0 : 0.6)
            .animation(.spring(response: 0.75, dampingFraction: 0.9), value: place)
            .contentShape(Rectangle())
            .onHover { hovering = $0 && synced }
            .pointerStyle(synced ? .link : .default)
            .onTapGesture { if synced { seek() } }
    }

    private var opacity: Double {
        if hovering && place != .current { return 0.75 }
        switch place {
        case .current: return 1
        case .past: return 0.26
        case .upcoming: return 0.4
        case .plain: return 0.75
        }
    }
}

struct LyricsStrip: View {
    @Bindable var player: Player
    let lyrics: Lyrics
    let size: CGFloat

    var body: some View {
        let index = player.lyricIndex ?? -1
        AnchoredLines(lines: lyrics.lines, index: index, before: 1, after: 3, anchor: 0.34, spacing: size * 0.38) { line in
            let current = line.id == index
            Text(line.text.isEmpty ? "· · ·" : line.text)
                .font(.system(size: size, weight: .bold))
                .tracking(-size * 0.03)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .rasterized()
                .opacity(current ? 1 : line.id < index ? 0.22 : 0.34)
                .scaleEffect(current ? 1 : 0.9, anchor: .leading)
                .blur(radius: current ? 0 : 1.5)
        }
        .frame(height: size * 6.4)
        .clipShape(Rectangle())
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.82),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
    }
}

struct AnchoredLines<Row: View>: View {
    let lines: [LyricLine]
    let index: Int
    let before: Int
    let after: Int
    let anchor: CGFloat
    let spacing: CGFloat
    @ViewBuilder let row: (LyricLine) -> Row
    @State private var heights: [Int: CGFloat] = [:]

    var body: some View {
        GeometryReader { geo in
            let focus = min(max(index, 0), max(lines.count - 1, 0))
            let lower = max(0, focus - before)
            let upper = min(lines.count - 1, focus + after)
            let estimate = heights.values.min() ?? 24
            let above = (lower..<max(lower, focus)).reduce(CGFloat(0)) { $0 + (heights[$1] ?? estimate) + spacing }
            VStack(alignment: .leading, spacing: spacing) {
                if lower <= upper {
                    ForEach(lines[lower...upper]) { line in
                        row(line)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[line.id] = $0 }
                            .transition(.opacity)
                    }
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .offset(y: geo.size.height * anchor - above)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .animation(.spring(response: 0.75, dampingFraction: 0.9), value: focus)
        }
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

extension View {
    @ViewBuilder
    func rasterized(_ enabled: Bool = true) -> some View {
        if enabled {
            padding(8).drawingGroup().padding(-8)
        } else {
            self
        }
    }
}
