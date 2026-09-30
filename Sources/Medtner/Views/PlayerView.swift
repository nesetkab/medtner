import SwiftUI

struct HoverTag: Equatable {
    let tile: Tile
    let y: CGFloat
}

struct PlayerView: View {
    @Bindable var player: Player
    @State private var searchOpen = false
    @State private var hoverTag: HoverTag?
    @FocusState private var searchFocused: Bool

    private let cover: CGFloat = 222

    var body: some View {
        ZStack(alignment: .topLeading) {
            Palette.background
                .ignoresSafeArea()
                .gesture(WindowDragGesture())

            HStack(alignment: .top, spacing: 0) {
                SeekRail(player: player)
                    .padding(.top, 46)
                    .padding(.bottom, 28)
                    .padding(.leading, 18)
                    .zIndex(4)

                leftColumn
                    .padding(.leading, 26)
                    .padding(.vertical, 26)
                    .zIndex(2)

                center
                    .padding(.vertical, 26)
                    .padding(.horizontal, 18)
                    .zIndex(1)

                ShelfColumn(player: player, hoverTag: $hoverTag)
                    .frame(width: 100)
                    .padding(.trailing, 26)
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
        .frame(width: 716, height: 465)
        .foregroundStyle(.white)
        .onReceive(NotificationCenter.default.publisher(for: .medtnerSearch)) { _ in openSearch() }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrackHeading(player: player)
                .frame(width: searchOpen || player.opened != nil ? cover + 20 : 400, height: 92, alignment: .topLeading)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: searchOpen || player.opened != nil)
                .frame(width: cover, alignment: .leading)

            ZStack {
                AmbientRipples(color: player.accent, active: player.isPlaying, size: cover, radius: 22)
                    .frame(width: cover * 1.3, height: cover * 1.3)
                    .allowsHitTesting(false)
                CoverArt(player: player, size: cover)
                    .trackMenu(player.track?.uri, player: player)
            }
            .frame(width: cover, height: cover)

            Spacer(minLength: 16)

            VolumeBar(player: player, width: cover - 36)
                .padding(.bottom, 20)

            Transport(player: player, spacing: 22, extras: true)
        }
        .frame(width: cover, alignment: .leading)
    }

    private var center: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
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
                if let opened = player.opened, !searchOpen {
                    CollectionPanel(player: player, collection: opened)
                        .padding(.top, 6)
                        .id(opened.tile.id)
                        .transition(.asymmetric(insertion: .offset(x: 40).combined(with: .opacity), removal: .opacity))
                }
                if searchOpen {
                    VStack(alignment: .leading, spacing: 6) {
                        SearchField(player: player, focused: $searchFocused) { closeSearch() }
                        SearchResults(player: player) { closeSearch() }
                    }
                    .padding(.top, 6)
                    .transition(.asymmetric(insertion: .offset(y: -12).combined(with: .opacity), removal: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

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
            .frame(maxWidth: 220, alignment: .trailing)
            .padding(.trailing, 146)
            .offset(y: hoverTag.y - 20)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .id(hoverTag.tile.id)
            .allowsHitTesting(false)
        }
    }

    private func openSearch() {
        player.closeCollection()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { searchOpen = true }
        player.searching = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchFocused = true }
    }

    private func closeSearch() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { searchOpen = false }
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
            Text(title)
                .font(.system(size: 46, weight: .bold))
                .tracking(-1.8)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .id("t-" + title)
                .transition(TextReveal())
            Text(artist)
                .font(.system(size: 23, weight: .regular))
                .tracking(-0.8)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .id("a-" + artist)
                .transition(TextReveal())
                .offset(y: -3)
        }
    }
}

struct CoverArt: View {
    @Bindable var player: Player
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.tile)
            Art(url: player.artURL600, radius: 22)
                .id(player.artURL600)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.86).combined(with: .opacity).combined(with: .offset(y: -18)),
                        removal: .scale(scale: 1.08).combined(with: .opacity)
                    )
                )
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .scaleEffect(player.isPlaying ? 1 : 0.96)
        .shadow(color: .black.opacity(0.5), radius: player.isPlaying ? 18 : 8, y: 8)
        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: player.isPlaying)
        .hoverLift(1.015)
    }
}

extension Notification.Name {
    static let medtnerSearch = Notification.Name("medtner.search")
}
