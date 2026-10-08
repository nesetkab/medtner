import SwiftUI

struct DevicePicker: View {
    @Bindable var player: Player

    private var elsewhere: Device? {
        guard let device = player.device, device.name != Engine.deviceName else { return nil }
        return device
    }

    var body: some View {
        Menu {
            Picker("Play On", selection: selection) {
                ForEach(player.devices) { device in
                    Label(device.name, systemImage: device.symbol).tag(device.id)
                }
            }
            .pickerStyle(.inline)
            if player.devices.isEmpty {
                Text("No devices found")
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: player.device?.symbol ?? "hifispeaker")
                    .font(.system(size: 16, weight: .semibold))
                if let elsewhere {
                    Text(elsewhere.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: 140, alignment: .leading)
                }
            }
            .foregroundStyle(elsewhere == nil ? Color(white: 0.55) : player.accentColor)
            .frame(height: 40)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverLift(1.1)
        .pointerStyle(.link)
        .onHover { if $0 { Task { await player.loadDevices() } } }
        .help(elsewhere.map { "Playing on \($0.name)" } ?? "Choose where to play")
    }

    private var selection: Binding<String?> {
        Binding(
            get: { player.device?.id },
            set: { id in
                guard let device = player.devices.first(where: { $0.id == id }) else { return }
                player.transfer(to: device)
            }
        )
    }
}

extension Device {
    var symbol: String {
        switch type.lowercased() {
        case "computer": "laptopcomputer"
        case "smartphone": "iphone"
        case "tablet": "ipad"
        case "tv", "castvideo", "stb": "tv"
        case "gameconsole": "gamecontroller"
        case "automobile": "car"
        default: "hifispeaker"
        }
    }
}
