import AppKit
import SwiftUI

struct Onboarding: View {
    @Bindable var player: Player
    @State private var clientID = UserDefaults.standard.string(forKey: "clientID") ?? ""
    @State private var working = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Capsule()
                .fill(Color(white: 0.55))
                .frame(width: 3)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(nsColor: Palette.defaultAccent))
                        .frame(width: 15, height: 15)
                        .offset(y: progressOffset)
                        .animation(.spring(response: 0.7, dampingFraction: 0.6), value: player.phase)
                }
                .frame(width: 26)
                .padding(.vertical, 30)
                .padding(.leading, 18)

            VStack(alignment: .leading, spacing: 0) {
                Text("Medtner")
                    .font(.system(size: 46, weight: .bold))
                    .tracking(-1.8)
                Text(subtitle)
                    .font(.system(size: 23))
                    .tracking(-0.8)
                    .foregroundStyle(Color(white: 0.9))
                    .id(subtitle)
                    .transition(TextReveal())
                    .offset(y: -3)

                Spacer(minLength: 24)

                Group {
                    switch player.phase {
                    case .needsClientID: clientStep
                    case .needsSignIn: signInStep
                    case .needsEngineLogin: engineStep
                    case .ready: EmptyView()
                    }
                }
                .transition(.asymmetric(insertion: .offset(y: 20).combined(with: .opacity), removal: .opacity))

                if let error = player.lastError {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 1, green: 0.5, blue: 0.5))
                        .padding(.top, 10)
                }

                Spacer(minLength: 24)
            }
            .padding(.leading, 26)
            .padding(.vertical, 26)
            .padding(.trailing, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Layout.width, height: Layout.height)
        .background(Palette.background)
        .foregroundStyle(.white)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: player.phase)
    }

    private var progressOffset: CGFloat {
        switch player.phase {
        case .needsClientID: 0
        case .needsSignIn: 160
        case .needsEngineLogin: 320
        case .ready: 480
        }
    }

    private var subtitle: String {
        switch player.phase {
        case .needsClientID: "Connect a Spotify app"
        case .needsSignIn: "Sign in to Spotify"
        case .needsEngineLogin: "Wake up the speaker"
        case .ready: "Ready"
        }
    }

    private var clientStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            step("1", "Create an app at developer.spotify.com. Tick Web API.") {
                NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard/create")!)
            }
            HStack(spacing: 10) {
                Text("2").font(.system(size: 13, weight: .black)).foregroundStyle(Palette.muted).frame(width: 14)
                Text("Add this redirect URI")
                    .font(.system(size: 14, weight: .medium))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Auth.redirectURI, forType: .string)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { copied = true }
                } label: {
                    HStack(spacing: 6) {
                        Text(Auth.redirectURI).font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(white: 0.17)))
                }
                .buttonStyle(PressStyle(scale: 0.94))
            }
            HStack(spacing: 10) {
                Text("3").font(.system(size: 13, weight: .black)).foregroundStyle(Palette.muted).frame(width: 14)
                TextField("", text: $clientID, prompt: Text("Paste the Client ID").foregroundStyle(Color(white: 0.35)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.15)))
                    .frame(width: 330)
                    .onSubmit(save)
                pill("Continue", enabled: clientID.count >= 20, action: save)
            }
        }
    }

    private var signInStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your browser will open. Approve Medtner and come back.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(white: 0.8))
            HStack(spacing: 10) {
                pill(working ? "Waiting for Spotify…" : "Sign in", enabled: !working) {
                    working = true
                    Task {
                        await player.signIn()
                        working = false
                    }
                }
                Button("Change Client ID") {
                    UserDefaults.standard.removeObject(forKey: "clientID")
                    Task { await player.resolvePhase() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
            }
        }
    }

    private var engineStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            if player.engineState == .missing {
                Text("Medtner's speaker engine is missing. Install it with:")
                    .font(.system(size: 14, weight: .medium))
                Text("brew install librespot")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                Text("Medtner plays audio itself, so the Spotify app can stay closed. Approve the speaker once in your browser.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(white: 0.8))
                    .frame(width: 420, alignment: .leading)
                HStack(spacing: 10) {
                    EqualizerBars(playing: true, color: Color(nsColor: Palette.defaultAccent))
                        .frame(width: 18, height: 16)
                    Text("Waiting for approval")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
        }
    }

    private func step(_ number: String, _ text: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(number).font(.system(size: 13, weight: .black)).foregroundStyle(Palette.muted).frame(width: 14)
            Text(text).font(.system(size: 14, weight: .medium))
            Button(action: action) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color(white: 0.17)))
            }
            .buttonStyle(PressStyle())
        }
    }

    private func pill(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(enabled ? Color(nsColor: Palette.defaultAccent) : Color(white: 0.3)))
        }
        .buttonStyle(PressStyle(scale: 0.93))
        .disabled(!enabled)
    }

    private func save() {
        guard clientID.count >= 20 else { return }
        Task { await player.setClientID(clientID) }
    }
}

struct EqualizerBars: View {
    let playing: Bool
    let color: Color
    @State private var phase = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                let heights: [CGFloat] = [0.9, 0.5, 1.0, 0.65]
                let low: [CGFloat] = [0.3, 0.8, 0.4, 0.25]
                Capsule()
                    .fill(color)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .scaleEffect(y: playing ? (phase ? heights[i] : low[i]) : 0.2, anchor: .bottom)
                    .animation(
                        playing
                            ? .easeInOut(duration: 0.32 + Double(i) * 0.07).repeatForever(autoreverses: true)
                            : .spring(response: 0.3),
                        value: phase
                    )
                    .animation(.spring(response: 0.3), value: playing)
            }
        }
        .onAppear { phase = true }
    }
}
