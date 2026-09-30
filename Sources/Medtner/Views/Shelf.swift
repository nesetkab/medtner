import SwiftUI

struct ShelfColumn: View {
    @Bindable var player: Player
    @Binding var hoverTag: HoverTag?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 20) {
                ForEach(Array(player.shelf.enumerated()), id: \.element.id) { index, tile in
                    ShelfTile(tile: tile, index: index, accent: player.accentColor) { hovering, y in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if hovering {
                                hoverTag = HoverTag(tile: tile, y: y)
                            } else if hoverTag?.tile.id == tile.id {
                                hoverTag = nil
                            }
                        }
                    } action: {
                        if player.shelfMode == .queue {
                            player.playFromQueue(index)
                        } else {
                            player.play(tile)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .offset(x: 130).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
                if player.shelf.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(white: 0.16))
                            .frame(width: 100, height: 100)
                    }
                }
            }
            .padding(.vertical, 28)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: player.shelf.map(\.id))
        }
        .scrollClipDisabled(false)
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.04),
                .init(color: .black, location: 0.9),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
    }
}

struct ShelfTile: View {
    let tile: Tile
    let index: Int
    let accent: Color
    let onHover: (Bool, CGFloat) -> Void
    let action: () -> Void
    @State private var hovering = false
    @State private var appeared = false

    var body: some View {
        GeometryReader { geo in
            Button(action: action) {
                Art(url: tile.art, radius: 18)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(accent, lineWidth: hovering ? 3 : 0)
                    }
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 26, weight: .black))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 8)
                            .scaleEffect(hovering ? 1 : 0.4)
                            .opacity(hovering ? 1 : 0)
                    }
            }
            .buttonStyle(PressStyle(scale: 0.9))
            .scaleEffect(hovering ? 1.06 : 1)
            .rotationEffect(.degrees(hovering ? (index.isMultiple(of: 2) ? -2.5 : 2.5) : 0))
            .onHover { hover in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { hovering = hover }
                onHover(hover, geo.frame(in: .named("root")).midY)
            }
        }
        .frame(width: 100, height: 100)
        .offset(x: appeared ? 0 : 60)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75).delay(Double(min(index, 8)) * 0.045)) {
                appeared = true
            }
        }
    }
}

struct ShelfTabs: View {
    @Bindable var player: Player
    @Namespace private var dot

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(ShelfMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { player.shelfMode = mode }
                } label: {
                    HStack(spacing: 8) {
                        Text(mode.rawValue)
                            .font(.system(size: 13, weight: player.shelfMode == mode ? .bold : .medium))
                            .foregroundStyle(player.shelfMode == mode ? Color.white : Palette.muted)
                        ZStack {
                            if player.shelfMode == mode {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(player.accentColor)
                                    .matchedGeometryEffect(id: "dot", in: dot)
                            }
                        }
                        .frame(width: 7, height: 7)
                    }
                }
                .buttonStyle(PressStyle(scale: 0.94))
            }
        }
    }
}

struct SearchField: View {
    @Bindable var player: Player
    var focused: FocusState<Bool>.Binding
    let close: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            TextField("", text: Binding(get: { player.searchText }, set: { player.search($0) }),
                      prompt: Text("Search").foregroundStyle(Color(white: 0.35)))
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.6)
                .focused(focused)
                .onSubmit {
                    if let first = player.searchResults.first {
                        player.play(first)
                        close()
                    }
                }
                .onExitCommand(perform: close)
            Rectangle()
                .fill(player.accentColor)
                .frame(height: 3)
        }
        .frame(width: 200)
    }
}

struct SearchResults: View {
    @Bindable var player: Player
    let close: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Array(player.searchResults.enumerated()), id: \.element.id) { index, tile in
                    SearchRow(tile: tile, index: index, accent: player.accentColor) {
                        player.play(tile)
                        close()
                    } enqueue: {
                        player.enqueue(tile)
                    }
                }
            }
            .padding(.top, 10)
        }
    }
}

struct SearchRow: View {
    let tile: Tile
    let index: Int
    let accent: Color
    let play: () -> Void
    let enqueue: () -> Void
    @State private var hovering = false
    @State private var appeared = false
    @State private var queued = false

    var body: some View {
        HStack(spacing: 10) {
            Art(url: tile.art, radius: 7)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(tile.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(tile.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if hovering && !tile.playURI.contains(":album:") && !tile.playURI.contains(":playlist:") {
                Button {
                    enqueue()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { queued = true }
                } label: {
                    Image(systemName: queued ? "checkmark" : "text.line.last.and.arrowtriangle.forward")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(queued ? accent : .white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(PressStyle())
                .help("Add to queue")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering ? Color(white: 0.16) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: play)
        .onHover { hover in withAnimation(.easeOut(duration: 0.15)) { hovering = hover } }
        .offset(y: appeared ? 0 : 14)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8).delay(Double(min(index, 10)) * 0.03)) {
                appeared = true
            }
        }
    }
}
