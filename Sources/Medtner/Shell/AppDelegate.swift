import AppKit
import SwiftUI

struct RootView: View {
    @Bindable var player: Player

    var body: some View {
        ZStack {
            if player.phase == .ready {
                PlayerView(player: player)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                Onboarding(player: player)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: player.phase == .ready)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let player = Player.shared
    private var window: NSWindow!
    private var status: StatusItemController!
    private var pill: PillPanel?
    private var keyMonitor: Any?
    private var windowVisible = false { didSet { updateSurfaces() } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()

        status = StatusItemController(player: player) { [weak self] in self?.menuItems() ?? [] }
        status.onOpenChange = { [weak self] _ in self?.updateSurfaces() }

        installKeys()
        player.boot()
        window.makeKeyAndOrderFront(nil)
        if UserDefaults.standard.bool(forKey: "pill") { togglePill() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        player.engine.stop()
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 716, height: 465),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1)
        window.isReleasedWhenClosed = false
        window.title = "Medtner"
        window.appearance = NSAppearance(named: .darkAqua)
        window.delegate = self
        let host = NSHostingView(rootView: RootView(player: player))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(NSSize(width: 716, height: 465))
        window.setFrameAutosaveName("MedtnerMain")
        if !window.setFrameUsingName("MedtnerMain") { window.center() }
        window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 716, height: 465)), display: false)
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.windowVisible = self.window.occlusionState.contains(.visible)
            }
        }
    }

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func updateSurfaces() {
        player.visibleSurfaces = (windowVisible ? 1 : 0) + (status?.isOpen == true ? 1 : 0) + (pill != nil ? 1 : 0)
    }

    @objc func togglePill() {
        if let pill {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                pill.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor in
                    self?.pill?.orderOut(nil)
                    self?.pill = nil
                    self?.updateSurfaces()
                }
            })
            UserDefaults.standard.set(false, forKey: "pill")
            return
        }
        let size = NSSize(width: 380, height: 150)
        let panel = PillPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: PillView(player: player).preferredColorScheme(.dark))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        if let screen = NSScreen.main {
            let frame = screen.frame
            let top = screen.visibleFrame.maxY
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: top - size.height - 6))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }
        pill = panel
        UserDefaults.standard.set(true, forKey: "pill")
        updateSurfaces()
    }

    @objc func toggleTicker() {
        let current = UserDefaults.standard.object(forKey: "ticker") as? Bool ?? true
        UserDefaults.standard.set(!current, forKey: "ticker")
        status.render()
    }

    @objc func toggleVinyl() {
        showWindow()
        NotificationCenter.default.post(name: .medtnerVinyl, object: nil)
    }

    @objc func openSearch() {
        showWindow()
        NotificationCenter.default.post(name: .medtnerSearch, object: nil)
    }

    @objc func openWindowAction() { showWindow() }
    @objc func playPause() { player.togglePlay() }
    @objc func nextTrack() { player.next() }
    @objc func previousTrack() { player.previous() }
    @objc func signOut() { Task { await player.signOut() } }

    @objc private func pickDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? Device else { return }
        player.transfer(to: device)
    }

    private func menuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        func add(_ title: String, _ action: Selector, key: String = "", on: Bool? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            if let on { item.state = on ? .on : .off }
            items.append(item)
        }

        let devices = NSMenuItem(title: "Play On", action: nil, keyEquivalent: "")
        let list = NSMenu()
        for device in player.devices {
            let entry = NSMenuItem(title: device.name, action: #selector(pickDevice(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = device
            entry.state = device.id == player.device?.id ? .on : .off
            list.addItem(entry)
        }
        if player.devices.isEmpty {
            list.addItem(NSMenuItem(title: "No devices", action: nil, keyEquivalent: ""))
        }
        devices.submenu = list
        items.append(devices)
        items.append(.separator())

        add("Open Medtner", #selector(openWindowAction), key: "0")
        add("Pill Mode", #selector(togglePill), on: pill != nil)
        add("Scrolling Title", #selector(toggleTicker), on: UserDefaults.standard.object(forKey: "ticker") as? Bool ?? true)
        items.append(.separator())
        add("Sign Out", #selector(signOut))
        let quit = NSMenuItem(title: "Quit Medtner", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        items.append(quit)
        return items
    }

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Medtner", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Medtner", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Medtner", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Search", action: #selector(openSearch), keyEquivalent: "f").target = self
        editItem.submenu = edit
        main.addItem(editItem)

        let viewItem = NSMenuItem()
        let view = NSMenu(title: "View")
        let vinyl = view.addItem(withTitle: "Vinyl", action: #selector(toggleVinyl), keyEquivalent: "r")
        vinyl.keyEquivalentModifierMask = [.command, .shift]
        let pillItem = view.addItem(withTitle: "Pill Mode", action: #selector(togglePill), keyEquivalent: "p")
        pillItem.keyEquivalentModifierMask = [.command, .shift]
        view.addItem(withTitle: "Scrolling Title in Menu Bar", action: #selector(toggleTicker), keyEquivalent: "")
        for item in view.items { item.target = self }
        viewItem.submenu = view
        main.addItem(viewItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Player", action: #selector(openWindowAction), keyEquivalent: "0").target = self
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    private func installKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, self.player.phase == .ready else { return event }
            if self.window.firstResponder is NSText { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.subtracting([.function, .numericPad]).isEmpty else { return event }
            switch event.keyCode {
            case 53: self.player.closeCollection()
            case 49: self.player.togglePlay()
            case 123: self.player.previous()
            case 124: self.player.next()
            case 126: self.player.setVolume(self.player.volume + 5)
            case 125: self.player.setVolume(self.player.volume - 5)
            default:
                switch event.charactersIgnoringModifiers {
                case "/": self.openSearch()
                case "v": self.toggleVinyl()
                case "p": self.togglePill()
                case "s": self.player.toggleShuffle()
                default: return event
                }
            }
            return nil
        }
    }
}
