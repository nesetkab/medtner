import AppKit
import QuartzCore

final class StatusGlyph: NSView {
    private let bars: [CALayer] = (0..<4).map { _ in CALayer() }
    private let tickerClip = CALayer()
    private let ticker = CATextLayer()
    private let fade = CAGradientLayer()
    private var text = ""
    private var playing = false
    private var accent = Palette.defaultAccent
    var showTicker = true

    static let barWidth: CGFloat = 3
    static let eqWidth: CGFloat = 4 * barWidth + 3 * 2
    static let tickerWidth: CGFloat = 118

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in bars {
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.cornerRadius = 1.5
            layer?.addSublayer(bar)
        }
        tickerClip.masksToBounds = true
        tickerClip.mask = fade
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, 0.06, 0.88, 1]
        ticker.fontSize = 12
        ticker.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        ticker.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        ticker.alignmentMode = .left
        tickerClip.addSublayer(ticker)
        layer?.addSublayer(tickerClip)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var preferredWidth: CGFloat {
        showTicker && !text.isEmpty ? Self.eqWidth + 8 + Self.tickerWidth + 6 : Self.eqWidth + 10
    }

    func update(text: String, playing: Bool, accent: NSColor) {
        let textChanged = text != self.text
        let playingChanged = playing != self.playing
        let accentChanged = accent != self.accent
        self.text = text
        self.playing = playing
        self.accent = accent
        if accentChanged { applyColors() }
        if textChanged || playingChanged { needsLayout = true }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in bars { bar.backgroundColor = accent.cgColor }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ticker.foregroundColor = NSColor.labelColor.cgColor
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let h = bounds.height
        let eqHeight: CGFloat = 13
        let baseY = (h - eqHeight) / 2
        let heights: [CGFloat] = [0.75, 1.0, 0.55, 0.85]
        for (i, bar) in bars.enumerated() {
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

        tickerClip.isHidden = !(showTicker && !text.isEmpty)
        tickerClip.frame = CGRect(x: Self.eqWidth + 12, y: 0, width: Self.tickerWidth, height: h)
        fade.frame = tickerClip.bounds
        ticker.removeAnimation(forKey: "scroll")
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let single = (text as NSString).size(withAttributes: [.font: font]).width
        let lineY = (h - 15) / 2 - 0.5
        if single > Self.tickerWidth - 8 {
            let gap = "      •      "
            let segment = (text + gap as NSString).size(withAttributes: [.font: font]).width
            ticker.string = text + gap + text
            ticker.frame = CGRect(x: 4, y: lineY, width: segment * 2 + 20, height: 15)
            if playing {
                let scroll = CABasicAnimation(keyPath: "position.x")
                scroll.byValue = -segment
                scroll.duration = Double(segment) / 22
                scroll.repeatCount = .infinity
                scroll.beginTime = CACurrentMediaTime() + 1.2
                ticker.add(scroll, forKey: "scroll")
            }
        } else {
            ticker.string = text
            ticker.frame = CGRect(x: 4, y: lineY, width: single + 4, height: 15)
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
        let text = player.track.map { "\($0.name) — \($0.artistLine)" } ?? ""
        let ticker = UserDefaults.standard.object(forKey: "ticker") as? Bool ?? true
        if ticker != glyph.showTicker {
            glyph.showTicker = ticker
            glyph.needsLayout = true
        }
        glyph.update(text: text, playing: player.isPlaying, accent: player.accent)
        item.length = glyph.preferredWidth
        _ = (player.artwork, player.volume, player.shuffle, player.durationMs)
        guard isOpen else { return }
        nowPlaying.needsDisplay = true
        transport.sync()
        volume.needsDisplay = true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for view in [nowPlaying, transport, volume] as [NSView] {
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
