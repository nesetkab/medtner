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

struct MiniController: View {
    @Bindable var player: Player
    let openPlayer: () -> Void
    let togglePill: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Art(url: player.track?.artwork.best(near: 200), radius: 12)
                    .frame(width: 64, height: 64)
                    .id(player.track?.uri)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.track?.name ?? "Nothing playing")
                        .font(.system(size: 19, weight: .bold))
                        .tracking(-0.6)
                        .lineLimit(1)
                        .id("m-" + (player.track?.name ?? ""))
                        .transition(TextReveal())
                    Text(player.track?.artistLine ?? "Medtner")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(white: 0.75))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            ThinProgress(player: player)

            HStack {
                Transport(player: player, size: 20, spacing: 12)
                Spacer()
                Button { player.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(player.shuffle ? player.accentColor : Palette.muted)
                }
                .buttonStyle(PressStyle())
                DeviceMenu(player: player)
            }

            VolumeBar(player: player, width: 180)
                .scaleEffect(0.8, anchor: .leading)
                .frame(height: 18)

            Divider().overlay(Color(white: 0.2))

            HStack(spacing: 16) {
                footerButton("Open Medtner", "macwindow", action: openPlayer)
                footerButton("Pill", "capsule", action: togglePill)
                Spacer()
                footerButton("Quit", "power") { NSApp.terminate(nil) }
            }
        }
        .padding(18)
        .frame(width: 320)
        .background(Palette.background)
        .foregroundStyle(.white)
    }

    private func footerButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.8))
        }
        .buttonStyle(PressStyle(scale: 0.94))
    }
}

struct DeviceMenu: View {
    @Bindable var player: Player

    var body: some View {
        Menu {
            ForEach(player.devices) { device in
                Button {
                    player.transfer(to: device)
                } label: {
                    if device.id == player.device?.id {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Image(systemName: "hifispeaker.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(player.device?.name == Engine.deviceName ? Palette.muted : player.accentColor)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(player.device.map { "Playing on \($0.name)" } ?? "Devices")
        .task { await player.loadDevices() }
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
                    Transport(player: player, size: 16, spacing: 10)
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
