import SwiftUI

struct HoverTag: Equatable {
    let tile: Tile
    let y: CGFloat
}

enum Layout {
    static let width: CGFloat = 880
    static let height: CGFloat = 570
    static let cover: CGFloat = 296
    static let tile: CGFloat = 116
    static let margin: CGFloat = 30
}

struct PlayerView: View {
    @Bindable var player: Player
    @State private var searchOpen = false
    @AppStorage("lyrics") private var showLyrics = true
    @State private var hoverTag: HoverTag?
    @FocusState private var searchFocused: Bool

    private let cover = Layout.cover

    var body: some View {
        ZStack(alignment: .topLeading) {
            Palette.background
                .ignoresSafeArea()
                .gesture(WindowDragGesture())

            HStack(alignment: .top, spacing: 0) {
                SeekRail(player: player)
                    .padding(.top, 50)
                    .padding(.bottom, Layout.margin + 2)
                    .padding(.leading, 20)
                    .zIndex(4)

                leftColumn
                    .padding(.leading, 30)
                    .padding(.vertical, Layout.margin)
                    .zIndex(0)

                center
                    .padding(.vertical, Layout.margin)
                    .padding(.horizontal, 24)
                    .zIndex(1)

                ShelfColumn(player: player, hoverTag: $hoverTag)
                    .frame(width: Layout.tile + 24)
                    .padding(.leading, -12)
                    .padding(.trailing, Layout.margin - 12)
                    .zIndex(3)
            }
        }
        .coordinateSpace(name: "root")
        .overlay(alignment: .topTrailing) { hoverLabel }
        .overlay(alignment: .bottom) {
            if let toast = player.toast {
                Toast(text: toast, accent: player.accentColor)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: Layout.width, height: Layout.height)
        .foregroundStyle(.white)
        .onReceive(NotificationCenter.default.publisher(for: .medtnerSearch)) { _ in openSearch() }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrackHeading(player: player)
                .frame(width: searchOpen || player.opened != nil ? cover : 480, height: 104, alignment: .topLeading)
                .zIndex(1)
                .animation(.snappy(duration: 0.18), value: searchOpen || player.opened != nil)
                .frame(width: cover, alignment: .leading)

            ZStack {
                AmbientBlobs(player: player, colors: player.palette, playing: player.isPlaying, diameter: cover)
                    .frame(width: cover * 2.2, height: cover * 2.2)
                    .allowsHitTesting(false)
                CoverArt(player: player, size: cover)
                    .trackMenu(player.track?.uri, player: player)
            }
            .frame(width: cover, height: cover)
            .zIndex(-1)

            Spacer(minLength: 18)

            VolumeBar(player: player, width: cover - 36)
                .padding(.bottom, 24)
                .zIndex(1)

            Transport(player: player, size: 20, spacing: 28, extras: true)
                .zIndex(1)
        }
        .frame(width: cover, alignment: .leading)
    }

    private var center: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                LyricsToggle(on: $showLyrics, available: player.lyrics != nil, accent: player.accentColor)
                Button {
                    searchOpen ? closeSearch() : openSearch()
                } label: {
                    Magnifier()
                        .frame(width: 24, height: 24)
                        .padding(8)
                        .rotationEffect(.degrees(searchOpen ? -90 : 0))
                        .foregroundStyle(searchOpen ? player.accentColor : Color(white: 0.85))
                }
                .buttonStyle(PressStyle())
            }
            .frame(height: 50)

            ZStack(alignment: .topTrailing) {
                if showLyrics, let lyrics = player.lyrics, player.opened == nil, !searchOpen {
                    LyricsPanel(player: player, lyrics: lyrics)
                        .padding(.top, 48)
                        .opacity(hoverTag == nil ? 1 : 0.15)
                        .animation(.easeOut(duration: 0.15), value: hoverTag == nil)
                        .id(lyrics.trackURI)
                        .transition(.opacity)
                }
                if let opened = player.opened, !searchOpen {
                    CollectionPanel(player: player, collection: opened)
                        .padding(.top, 6)
                        .id(opened.tile.id)
                        .transition(.asymmetric(insertion: .offset(x: 40).combined(with: .opacity), removal: .opacity))
                }
                VStack(alignment: .leading, spacing: 6) {
                    SearchField(player: player, focused: $searchFocused) { closeSearch() }
                    SearchResults(player: player) { closeSearch() }
                }
                .padding(.top, 6)
                .offset(y: searchOpen ? 0 : -12)
                .opacity(searchOpen ? 1 : 0)
                .allowsHitTesting(searchOpen)
                .disabled(!searchOpen)
                .accessibilityHidden(!searchOpen)
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topTrailing)

            if !searchOpen && player.opened == nil {
                ShelfTabs(player: player)
                    .opacity(hoverTag == nil ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: hoverTag == nil)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var hoverLabel: some View {
        if let hoverTag, !searchOpen, player.opened == nil {
            VStack(alignment: .trailing, spacing: 2) {
                Text(hoverTag.tile.title)
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.3)
                Text(hoverTag.tile.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }
            .lineLimit(1)
            .frame(maxWidth: 280, alignment: .trailing)
            .padding(.trailing, Layout.tile + Layout.margin + 22)
            .offset(y: max(hoverTag.y - 20, 92))
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .id(hoverTag.tile.id)
            .allowsHitTesting(false)
        }
    }

    private func openSearch() {
        player.closeCollection()
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
}

struct TrackHeading: View {
    @Bindable var player: Player

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let title = player.track?.name ?? "Medtner"
            let artist = player.track?.artistLine ?? (player.phase == .ready ? "Press play" : "Not connected")
            Marquee(key: title) {
                Text(title)
                    .font(.system(size: 54, weight: .bold))
                    .tracking(-2.2)
                    .fixedSize()
            }
            .frame(height: 66)
            .id("t-" + title)
            .transition(TextReveal())
            Marquee(key: artist) {
                Text(artist)
                    .font(.system(size: 26, weight: .regular))
                    .tracking(-0.9)
                    .fixedSize()
            }
            .frame(height: 32)
            .id("a-" + artist)
            .transition(TextReveal())
            .offset(y: -3)
        }
    }
}

struct Marquee<Content: View>: View {
    let key: String
    @ViewBuilder let content: Content
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflow: CGFloat { max(0, textWidth - boxWidth) }

    var body: some View {
        content
            .background(GeometryReader { proxy in
                Color.clear.onAppear { textWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in textWidth = width }
            })
            .offset(x: offset)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { proxy in
                Color.clear.onAppear { boxWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in boxWidth = width }
            })
            .clipped()
            .mask(
                LinearGradient(stops: [
                    .init(color: offset < 0 ? .clear : .black, location: 0),
                    .init(color: .black, location: overflow > 0 ? 0.04 : 0),
                    .init(color: .black, location: overflow > 0 ? 0.92 : 1),
                    .init(color: overflow > 0 && offset > -overflow + 1 ? .clear : .black, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            )
            .task(id: "\(key)-\(Int(overflow))") {
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { offset = 0 }
                guard overflow > 0 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2.5))
                    guard !Task.isCancelled else { return }
                    let travel = overflow + 8
                    let duration = Double(travel) / 38
                    withAnimation(.linear(duration: duration)) { offset = -travel }
                    try? await Task.sleep(for: .seconds(duration + 2))
                    guard !Task.isCancelled else { return }
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.9)) { offset = 0 }
                }
            }
    }
}

struct CoverArt: View {
    @Bindable var player: Player
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Palette.tile)
            Art(url: player.artURL600, radius: 26)
                .id(player.artURL600)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.86).combined(with: .opacity).combined(with: .offset(y: -18)),
                        removal: .scale(scale: 1.08).combined(with: .opacity)
                    )
                )
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .scaleEffect(player.isPlaying ? 1 : 0.96)
        .shadow(color: .black.opacity(0.5), radius: player.isPlaying ? 18 : 8, y: 8)
        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: player.isPlaying)
        .hoverLift(1.015)
    }
}

extension Notification.Name {
    static let medtnerSearch = Notification.Name("medtner.search")
}
