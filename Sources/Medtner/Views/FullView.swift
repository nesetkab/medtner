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

struct FullView: View {
    @Bindable var player: Player
    @State private var controlsVisible = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack(alignment: .bottomLeading) {
                Color(red: 0.035, green: 0.035, blue: 0.04)

                AmbientBlobs(player: player, colors: player.palette, playing: player.isPlaying,
                             diameter: side * 1.3, spread: 1.15, glow: 1.9)
                    .frame(width: geo.size.width * 1.2, height: geo.size.height * 1.2)
                    .position(x: geo.size.width * 0.58, y: geo.size.height * 0.42)
                    .allowsHitTesting(false)

                clock
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(side * 0.06)

                placard(side: side)
                    .padding(side * 0.06)

                upNext
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(side * 0.06)

            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active = phase { reveal() }
            }
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .task(id: player.track?.uri) { await player.loadUpNext() }
        .onDisappear { NSCursor.setHiddenUntilMouseMoves(false) }
    }

    private var clock: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime.hour().minute())
                .font(.system(size: 44, weight: .light).monospacedDigit())
                .tracking(-1)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func placard(side: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: side * 0.03) {
            Art(url: player.artURL600, radius: 14)
                .frame(width: side * 0.16, height: side * 0.16)
                .id(player.artURL600)
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                .shadow(color: .black.opacity(0.45), radius: 24, y: 10)

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
                    LineProgress(fraction: player.fraction(), playing: player.isPlaying, durationMs: player.durationMs)
                        .frame(width: side * 0.3, height: 2)
                        .clipShape(Capsule())
                    let _ = player.progressEpoch
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("\(formatTime(player.position())) / \(formatTime(player.durationMs))")
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.top, 10)

                Transport(player: player, size: 20, spacing: 30, extras: true)
                    .padding(.top, 18)
                    .opacity(controlsVisible ? 1 : 0)
                    .offset(y: controlsVisible ? 0 : 6)
                    .allowsHitTesting(controlsVisible)
            }
            .frame(maxWidth: side * 0.9, alignment: .leading)
        }
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

    private func reveal() {
        NSCursor.setHiddenUntilMouseMoves(false)
        if !controlsVisible {
            withAnimation(.easeOut(duration: 0.25)) { controlsVisible = true }
        }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.5)) { controlsVisible = false }
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }
}
