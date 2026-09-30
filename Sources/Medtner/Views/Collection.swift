import SwiftUI

struct TrackMenu: ViewModifier {
    let uri: String?
    @Bindable var player: Player

    func body(content: Content) -> some View {
        content.contextMenu {
            if let uri, uri.contains(":track:") {
                Button("Add to Queue") { player.queueUp(uri) }
                Button("Save to Liked Songs") { player.like(uri) }
                Menu("Add to Playlist") {
                    ForEach(player.editable) { list in
                        Button(list.title) { player.add(uri, to: list) }
                    }
                    if player.editable.isEmpty {
                        Text("No playlists of yours yet")
                    }
                }
            }
        }
    }
}

extension View {
    func trackMenu(_ uri: String?, player: Player) -> some View {
        modifier(TrackMenu(uri: uri, player: player))
    }
}

struct CollectionPanel: View {
    @Bindable var player: Player
    let collection: OpenCollection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Group {
                    if let symbol = collection.tile.symbol {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(player.accentColor)
                            .overlay(Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(.black.opacity(0.75)))
                    } else {
                        Art(url: collection.tile.art, radius: 10)
                    }
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.tile.title)
                        .font(.system(size: 17, weight: .bold))
                        .tracking(-0.4)
                        .lineLimit(1)
                    Text(collection.tile.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { player.play(collection.tile) } label: {
                    Circle()
                        .fill(player.accentColor)
                        .frame(width: 34, height: 34)
                        .overlay(
                            Soft(shape: PlayPauseShape(progress: 0), corner: 1.2)
                                .foregroundStyle(.black.opacity(0.8))
                                .frame(width: 11, height: 13)
                                .offset(x: 1)
                        )
                }
                .buttonStyle(PressStyle(scale: 0.88))
                .help("Play")
                Button { player.closeCollection() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(PressStyle())
                .help("Close")
            }

            if collection.loading {
                EqualizerBars(playing: true, color: player.accentColor)
                    .frame(width: 18, height: 16)
                    .padding(.top, 8)
            } else if let note = collection.note {
                Text(note)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(collection.tracks.enumerated()), id: \.element.id) { index, tile in
                        SearchRow(tile: tile, index: index, accent: player.accentColor,
                                  current: tile.playURI == player.track?.uri) {
                            player.play(tile)
                        } enqueue: {
                            player.queueUp(tile.playURI)
                        }
                        .trackMenu(tile.playURI, player: player)
                    }
                }
                .padding(.bottom, 12)
            }
            .mask(
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.9),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
        }
    }
}

struct Toast: View {
    let text: String
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(white: 0.17)))
        .overlay(Capsule().strokeBorder(Color(white: 0.24), lineWidth: 1))
    }
}
