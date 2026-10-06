import AppKit
import QuartzCore

final class StatusGlyph: NSView {
    private let bars: [CALayer] = (0..<4).map { _ in CALayer() }
    private var playing = false
    private var accent = Palette.defaultAccent

    static let barWidth: CGFloat = 3
    static let width: CGFloat = 4 * barWidth + 3 * 2 + 10

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in bars {
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.cornerRadius = 1.5
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(playing: Bool, accent: NSColor) {
        if accent != self.accent {
            self.accent = accent
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for bar in bars { bar.backgroundColor = accent.cgColor }
            CATransaction.commit()
        }
        if playing != self.playing {
            self.playing = playing
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let eqHeight: CGFloat = 13
        let baseY = (bounds.height - eqHeight) / 2
        let heights: [CGFloat] = [0.75, 1.0, 0.55, 0.85]
        for (i, bar) in bars.enumerated() {
            bar.backgroundColor = accent.cgColor
            bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: eqHeight)
            bar.position = CGPoint(x: 5 + CGFloat(i) * (Self.barWidth + 2) + Self.barWidth / 2, y: baseY)
            bar.removeAnimation(forKey: "eq")
            if playing {
                let anim = CABasicAnimation(keyPath: "transform.scale.y")
                anim.fromValue = 0.2
                anim.toValue = heights[i]
                anim.duration = 0.28 + Double(i) * 0.09
                anim.autoreverses = true
                anim.repeatCount = .infinity
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                anim.timeOffset = Double(i) * 0.13
                bar.add(anim, forKey: "eq")
                bar.transform = CATransform3DIdentity
            } else {
                bar.transform = CATransform3DMakeScale(1, [0.35, 0.6, 0.25, 0.45][i], 1)
            }
        }
        CATransaction.commit()
    }
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let glyph = StatusGlyph(frame: .zero)
    private let player: Player
    private let menu = NSMenu()
    private let nowPlaying: NowPlayingRow
    private let transport: TransportRow
    private let volume: VolumeRow
    private let lyric: LyricLineRow
    private let extraItems: () -> [NSMenuItem]
    private var liveTimer: Timer?
    private(set) var isOpen = false
    var onOpenChange: ((Bool) -> Void)?

    init(player: Player, items: @escaping () -> [NSMenuItem]) {
        self.player = player
        self.extraItems = items
        nowPlaying = NowPlayingRow(player: player)
        transport = TransportRow(player: player)
        volume = VolumeRow(player: player)
        lyric = LyricLineRow(player: player)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        guard let button = item.button else { return }
        button.toolTip = "Medtner"
        button.addSubview(glyph)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            glyph.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            glyph.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            glyph.topAnchor.constraint(equalTo: button.topAnchor),
            glyph.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        observe()
    }

    private func observe() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    func render() {
        glyph.update(playing: player.isPlaying, accent: player.accent)
        item.length = StatusGlyph.width
        item.button?.toolTip = player.track.map { "\($0.name) — \($0.artistLine)" } ?? "Medtner"
        _ = (player.artwork, player.volume, player.shuffle, player.repeatMode, player.durationMs, player.lyricIndex, player.lyrics)
        guard isOpen else { return }
        nowPlaying.needsDisplay = true
        transport.sync()
        volume.needsDisplay = true
        lyric.needsDisplay = true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let showLyric = UserDefaults.standard.object(forKey: "lyrics") as? Bool ?? true
        let rows: [NSView] = showLyric && player.lyrics?.synced == true ? [nowPlaying, lyric, transport, volume] : [nowPlaying, transport, volume]
        for view in rows {
            let row = NSMenuItem()
            row.view = view
            menu.addItem(row)
        }
        menu.addItem(.separator())
        extraItems().forEach(menu.addItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        isOpen = true
        onOpenChange?(true)
        transport.sync()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.player.isPlaying else { return }
                self.nowPlaying.needsDisplay = true
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        liveTimer = timer
        Task { await player.loadDevices() }
    }

    func menuDidClose(_ menu: NSMenu) {
        isOpen = false
        liveTimer?.invalidate()
        liveTimer = nil
        onOpenChange?(false)
    }
}
