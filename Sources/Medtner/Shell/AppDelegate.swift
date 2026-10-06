import AppKit
import SwiftUI

struct RootView: View {
    @Bindable var player: Player

    var body: some View {
        ZStack {
            if player.phase == .ready && player.fullScreen {
                FullView(player: player)
                    .transition(.opacity)
            } else if player.phase == .ready {
                PlayerView(player: player)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                Onboarding(player: player)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: player.phase == .ready)
        .animation(.easeInOut(duration: 0.5), value: player.fullScreen)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let player = Player.shared
    private var window: NSWindow!
    private var status: StatusItemController!
    private var nowPlaying: NowPlaying?
    private var settingsWindow: NSWindow?
    private var keyMonitor: Any?
    private var windowVisible = false { didSet { updateSurfaces() } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        buildMenu()
        buildWindow()

        status = StatusItemController(player: player) { [weak self] in self?.menuItems() ?? [] }
        status.onOpenChange = { [weak self] _ in self?.updateSurfaces() }

        installKeys()
        nowPlaying = NowPlaying(player: player)
        player.boot()
        Updater.shared.start()
        window.makeKeyAndOrderFront(nil)
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
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
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
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self
        let host = FirstClickHostingView(rootView: RootView(player: player))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(NSSize(width: Layout.width, height: Layout.height))
        window.setFrameAutosaveName("MedtnerMain")
        if !window.setFrameUsingName("MedtnerMain") { window.center() }
        window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: Layout.width, height: Layout.height)), display: false)
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.windowVisible = self.window.occlusionState.contains(.visible)
            }
        }
    }

    func window(_ window: NSWindow, willUseFullScreenContentSize proposedSize: NSSize) -> NSSize {
        proposedSize
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        player.fullScreen = true
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        player.fullScreen = false
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        window.setContentSize(NSSize(width: Layout.width, height: Layout.height))
    }

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func updateSurfaces() {
        player.visibleSurfaces = (windowVisible ? 1 : 0) + (status?.isOpen == true ? 1 : 0)
    }

    @objc func openSearch() {
        showWindow()
        NotificationCenter.default.post(name: .medtnerSearch, object: nil)
    }

    @objc func openWindowAction() { showWindow() }
    @objc func installUpdate() { Updater.shared.install() }

    @objc func checkForUpdates() {
        openSettings()
        Task { await Updater.shared.check() }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.title = "Settings"
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1)
            window.isReleasedWhenClosed = false
            window.contentView = FirstClickHostingView(rootView: SettingsView(player: player, updater: Updater.shared)
                .padding(.top, 10)
                .preferredColorScheme(.dark))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
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
        add("Settings…", #selector(openSettings), key: ",")
        if let release = Updater.shared.available {
            add("Update to \(release.version)", #selector(installUpdate))
        }
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
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
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
            case 53:
                if self.window.styleMask.contains(.fullScreen) {
                    self.window.toggleFullScreen(nil)
                } else {
                    self.player.closeCollection()
                }
            case 49: self.player.togglePlay()
            case 123: self.player.previous()
            case 124: self.player.next()
            case 126: self.player.setVolume(self.player.volume + 5)
            case 125: self.player.setVolume(self.player.volume - 5)
            default:
                switch event.charactersIgnoringModifiers {
                case "/": self.openSearch()
                case "s": self.player.toggleShuffle()
                case "r": self.player.cycleRepeat()
                default: return event
                }
            }
            return nil
        }
    }
}
