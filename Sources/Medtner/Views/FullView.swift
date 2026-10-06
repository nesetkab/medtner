import AppKit
import QuartzCore
import SwiftUI

final class LineProgressView: NSView {
    private let fill = CALayer()
    private var fraction: Double = 0
    private var playing = false
    private var duration: Double = 0
    private var anchorTime = CACurrentMediaTime()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
        layer?.addSublayer(fill)
    }

    required init?(coder: NSCoder) { fatalError() }

    func apply(fraction: Double, playing: Bool, durationMs: Int) {
        let clamped = min(max(fraction, 0), 1)
        let drift = abs(current() - clamped) * Double(durationMs) / 1000
        guard playing != self.playing || drift > 0.6 || Double(durationMs) / 1000 != duration else { return }
        self.fraction = clamped
        self.playing = playing
        self.duration = Double(durationMs) / 1000
        anchorTime = CACurrentMediaTime()
        restart()
    }

    private func current() -> Double {
        guard playing, duration > 0 else { return fraction }
        return min(1, fraction + (CACurrentMediaTime() - anchorTime) / duration)
    }

    override func layout() {
        super.layout()
        fraction = current()
        anchorTime = CACurrentMediaTime()
        restart()
    }

    private func restart() {
        let width = bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.removeAllAnimations()
        fill.bounds = CGRect(x: 0, y: 0, width: width * CGFloat(fraction), height: bounds.height)
        fill.position = CGPoint(x: 0, y: bounds.midY)
        CATransaction.commit()
        let remaining = duration * (1 - fraction)
        guard playing, remaining > 0.05 else { return }
        let grow = CABasicAnimation(keyPath: "bounds.size.width")
        grow.fromValue = width * CGFloat(fraction)
        grow.toValue = width
        grow.duration = remaining
        grow.fillMode = .forwards
        grow.isRemovedOnCompletion = false
        fill.add(grow, forKey: "progress")
    }
}

struct LineProgress: NSViewRepresentable {
    let fraction: Double
    let playing: Bool
    let durationMs: Int

    func makeNSView(context: Context) -> LineProgressView { LineProgressView(frame: .zero) }

    func updateNSView(_ view: LineProgressView, context: Context) {
        view.apply(fraction: fraction, playing: playing, durationMs: durationMs)
    }
}

enum Grain {
    static let tile: NSImage = {
        let size = 160
        var generator = SystemRandomNumberGenerator()
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for i in 0..<(size * size) {
            let v = UInt8.random(in: 96...160, using: &generator)
            pixels[i * 4] = v
            pixels[i * 4 + 1] = v
            pixels[i * 4 + 2] = v
            pixels[i * 4 + 3] = 38
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: size * 4, bitsPerPixel: 32)!
        pixels.withUnsafeBytes { memcpy(rep.bitmapData!, $0.baseAddress!, size * size * 4) }
        let image = NSImage(size: NSSize(width: size / 2, height: size / 2))
        image.addRepresentation(rep)
        return image
    }()
}

struct FullView: View {
    @Bindable var player: Player
    @State private var controlsVisible = false
    @State private var hideTask: Task<Void, Never>?
    @State private var searchOpen = false
    @State private var hoverTag: HoverTag?
    @State private var scrub: Double?
    @AppStorage("lyrics") private var showLyrics = true
    @FocusState private var searchFocused: Bool

    private var pinned: Bool { searchOpen || player.opened != nil || scrub != nil }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let margin = side * 0.06
            ZStack(alignment: .bottomLeading) {
                Color(red: 0.035, green: 0.035, blue: 0.04)

                AmbientBlobs(player: player, colors: player.palette, playing: player.isPlaying,
                             diameter: side * 1.3, spread: 1.15, glow: 1.9)
                    .frame(width: geo.size.width * 1.2, height: geo.size.height * 1.2)
                    .position(x: geo.size.width * 0.58, y: geo.size.height * 0.42)
                    .allowsHitTesting(false)

                Image(nsImage: Grain.tile)
                    .resizable(resizingMode: .tile)
                    .blendMode(.overlay)
                    .opacity(0.5)
                    .allowsHitTesting(false)

                clock
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(margin)

                VStack(alignment: .leading, spacing: side * 0.05) {
                    if showLyrics, let lyrics = player.lyrics, lyrics.synced {
                        LyricsStrip(player: player, lyrics: lyrics, size: side * 0.05)
                            .frame(maxWidth: geo.size.width * 0.55, alignment: .leading)
                            .id(lyrics.trackURI)
                            .transition(.opacity)
                    }
                    placard(side: side)
                }
                .padding(margin)

                upNext
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(margin)
                    .opacity(controlsVisible ? 0 : 1)

                library
                    .padding(.top, margin + 118)
                    .padding(.trailing, margin - 12)
                    .padding(.bottom, margin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .opacity(controlsVisible ? 1 : 0)
                    .offset(x: controlsVisible ? 0 : 24)
                    .allowsHitTesting(controlsVisible)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active = phase { reveal() }
            }
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .onReceive(NotificationCenter.default.publisher(for: .medtnerSearch)) { _ in openSearch() }
        .onChange(of: pinned) { _, isPinned in if !isPinned { reveal() } }
        .onDisappear { NSCursor.setHiddenUntilMouseMoves(false) }
    }

    private var library: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    searchOpen ? closeSearch() : openSearch()
                } label: {
                    Magnifier()
                        .frame(width: 24, height: 24)
                        .padding(8)
                        .rotationEffect(.degrees(searchOpen ? -90 : 0))
                        .foregroundStyle(searchOpen ? player.accentColor : Color.white.opacity(0.85))
                }
                .buttonStyle(PressStyle())

                ZStack(alignment: .topTrailing) {
                    if let opened = player.opened, !searchOpen {
                        CollectionPanel(player: player, collection: opened)
                            .id(opened.tile.id)
                            .transition(.asymmetric(insertion: .offset(x: 40).combined(with: .opacity), removal: .opacity))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        SearchField(player: player, focused: $searchFocused) { closeSearch() }
                        SearchResults(player: player) { closeSearch() }
                    }
                    .opacity(searchOpen ? 1 : 0)
                    .offset(y: searchOpen ? 0 : -12)
                    .allowsHitTesting(searchOpen)
                    .disabled(!searchOpen)
                }
                .frame(width: 400)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.black.opacity(searchOpen || player.opened != nil ? 0.45 : 0))
                )

                if !searchOpen && player.opened == nil {
                    ShelfTabs(player: player)
                }
            }

            ShelfColumn(player: player, hoverTag: $hoverTag)
                .frame(width: Layout.tile + 24)
        }
    }

    private var clock: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(Self.timeFormatter.string(from: context.date))
                        .font(.system(size: 46, weight: .bold))
                        .tracking(-1.8)
                    if Self.usesMeridiem {
                        Text(context.date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated))).filter(\.isLetter).lowercased())
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Text(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day()).lowercased())
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(.white.opacity(0.92))
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = usesMeridiem ? "h:mm" : "HH:mm"
        return formatter
    }()

    private static let usesMeridiem: Bool = {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false
    }()

    private func placard(side: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: side * 0.03) {
            Art(url: player.artURL600, radius: 14)
                .frame(width: side * 0.16, height: side * 0.16)
                .id(player.artURL600)
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
                .trackMenu(player.track?.uri, player: player)

            VStack(alignment: .leading, spacing: 6) {
                Text(player.track?.name ?? "Medtner")
                    .font(.system(size: side * 0.05, weight: .bold))
                    .tracking(-side * 0.0018)
                    .lineLimit(2)
                    .id("ft-" + (player.track?.name ?? ""))
                    .transition(TextReveal())
                Text(subtitle)
                    .font(.system(size: side * 0.022, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .id("fa-" + subtitle)
                    .transition(TextReveal())
                HStack(spacing: 14) {
                    progress(width: side * 0.3)
                    let _ = player.progressEpoch
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let shown = scrub.map { Int(Double(player.durationMs) * $0) } ?? player.position()
                        Text("\(formatTime(shown)) / \(formatTime(player.durationMs))")
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.top, 10)

                HStack(spacing: 36) {
                    Transport(player: player, size: 20, spacing: 30, extras: true)
                    VolumeBar(player: player, width: 150)
                }
                .padding(.top, 18)
                .opacity(controlsVisible ? 1 : 0)
                .offset(y: controlsVisible ? 0 : 6)
                .allowsHitTesting(controlsVisible)
            }
            .frame(maxWidth: side * 0.9, alignment: .leading)
        }
    }

    private func progress(width: CGFloat) -> some View {
        let thick: CGFloat = controlsVisible ? 5 : 2
        return ZStack(alignment: .leading) {
            LineProgress(fraction: player.fraction(), playing: player.isPlaying, durationMs: player.durationMs)
                .opacity(scrub == nil ? 1 : 0)
            if let scrub {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(Color.white.opacity(0.9))
                    .frame(width: max(thick, width * CGFloat(scrub)))
            }
        }
        .frame(width: width, height: thick)
        .clipShape(Capsule())
        .frame(height: 16)
        .contentShape(Rectangle())
        .pointerStyle(.link)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { scrub = min(max($0.location.x / width, 0), 1) }
                .onEnded { value in
                    player.seek(to: min(max(value.location.x / width, 0), 1))
                    scrub = nil
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: thick)
    }

    private var subtitle: String {
        guard let track = player.track else { return "Press play" }
        let album = track.album?.name
        return album.map { "\(track.artistLine) · \($0)" } ?? track.artistLine
    }

    private var upNext: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if !player.upNext.isEmpty {
                Text("up next")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                ForEach(player.upNext.prefix(2)) { tile in
                    HStack(spacing: 12) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(tile.title)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            Text(tile.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                        Art(url: tile.art, radius: 8)
                            .frame(width: 40, height: 40)
                    }
                    .frame(maxWidth: 320, alignment: .trailing)
                    .transition(.opacity.combined(with: .offset(x: 12)))
                }
            }
        }
        .animation(.easeOut(duration: 0.4), value: player.upNext.map(\.id))
    }

    private func openSearch() {
        player.closeCollection()
        reveal()
        withAnimation(.snappy(duration: 0.2)) { searchOpen = true }
        player.searching = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if searchOpen { searchFocused = true }
        }
    }

    private func closeSearch() {
        withAnimation(.snappy(duration: 0.2)) { searchOpen = false }
        player.searching = false
        searchFocused = false
        player.search("")
    }

    private func reveal() {
        NSCursor.setHiddenUntilMouseMoves(false)
        if !controlsVisible {
            withAnimation(.easeOut(duration: 0.25)) { controlsVisible = true }
        }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !pinned else { return }
            withAnimation(.easeIn(duration: 0.5)) { controlsVisible = false }
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }
}
