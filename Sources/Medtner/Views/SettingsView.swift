import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var player: Player
    @Bindable var updater: Updater
    @AppStorage("bitrate") private var bitrate = 320
    @AppStorage("normalize") private var normalize = true
    @AppStorage("lyrics") private var showLyrics = true
    @AppStorage("lyricsOffset") private var lyricsOffset = 0
    @AppStorage("autoUpdate") private var autoUpdate = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var engineDirty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            section("Playback") {
                row("Audio quality") {
                    Picker("", selection: $bitrate) {
                        Text("Normal").tag(96)
                        Text("High").tag(160)
                        Text("Very high").tag(320)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 230)
                }
                row("Even out loudness") {
                    Toggle("", isOn: $normalize).toggleStyle(.switch).labelsHidden()
                }
                if engineDirty {
                    HStack {
                        Text("Applies after the speaker restarts. Playback pauses for a moment.")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                        Spacer()
                        Button("Restart now") {
                            player.engine.restart()
                            engineDirty = false
                        }
                        .buttonStyle(PressStyle(scale: 0.94, hover: 1.05))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(player.accentColor)
                    }
                    .transition(.opacity)
                }
            }

            section("Lyrics") {
                row("Show lyrics") {
                    Toggle("", isOn: $showLyrics).toggleStyle(.switch).labelsHidden()
                }
                row("Timing") {
                    HStack(spacing: 10) {
                        Text("earlier")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                        Slider(value: Binding(get: { Double(lyricsOffset) }, set: { lyricsOffset = Int($0.rounded()) }),
                               in: -1000...1000, step: 50)
                            .frame(width: 150)
                        Text("later")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                        Text(lyricsOffset == 0 ? "0s" : String(format: "%+.2fs", Double(-lyricsOffset) / 1000))
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(Palette.muted)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            section("App") {
                row("Open at login") {
                    Toggle("", isOn: $launchAtLogin).toggleStyle(.switch).labelsHidden()
                }
                row("Update automatically") {
                    Toggle("", isOn: $autoUpdate).toggleStyle(.switch).labelsHidden()
                }
                row("Version \(Updater.currentVersion)") {
                    HStack(spacing: 12) {
                        if let release = updater.available {
                            Button(updater.installing ? "Updating…" : "Update to \(release.version)") { updater.install() }
                                .buttonStyle(PressStyle(scale: 0.94, hover: 1.05))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(player.accentColor)
                                .disabled(updater.installing)
                        } else {
                            Text(updater.checking ? "Checking…" : updater.checkedOnce ? "Up to date" : "")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                            Button("Check now") { Task { await updater.check() } }
                                .buttonStyle(PressStyle(scale: 0.94, hover: 1.05))
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
            }

            section("Account") {
                row("Spotify") {
                    Button("Sign out") { Task { await player.signOut() } }
                        .buttonStyle(PressStyle(scale: 0.94, hover: 1.05))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 0.5, blue: 0.5))
                }
            }
        }
        .padding(28)
        .frame(width: 480)
        .tint(player.accentColor)
        .background(Palette.background)
        .foregroundStyle(.white)
        .animation(.snappy(duration: 0.2), value: engineDirty)
        .onChange(of: bitrate) { _, _ in engineDirty = true }
        .onChange(of: normalize) { _, _ in engineDirty = true }
        .onChange(of: showLyrics) { _, _ in player.syncLyrics() }
        .onChange(of: lyricsOffset) { _, _ in player.syncLyrics() }
        .onChange(of: launchAtLogin) { _, on in
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.lowercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 12, content: content)
        }
    }

    private func row<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
            Spacer(minLength: 16)
            control()
        }
        .frame(minHeight: 24)
    }
}
