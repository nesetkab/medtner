import AppKit
import Observation
import SwiftUI

enum ShelfMode: String, CaseIterable, Identifiable {
    case queue = "Queue"
    case recent = "Recent"
    case playlists = "Playlists"
    var id: String { rawValue }
}

struct OpenCollection: Equatable {
    let tile: Tile
    var tracks: [Tile] = []
    var loading = true
    var note: String?
}

enum Phase: Equatable {
    case needsClientID
    case needsSignIn
    case needsEngineLogin
    case ready
}

@MainActor
@Observable
final class Player {
    static let shared = Player()

    var phase: Phase = .needsClientID
    var engineState: Engine.State = .off
    var lastError: String?

    var track: Track?
    var isPlaying = false
    var durationMs = 1
    var volume = 60
    var shuffle = false
    var device: Device?
    var devices: [Device] = []
    var contextURI: String?

    var artwork: NSImage?
    var accent = Palette.defaultAccent
    var palette: [NSColor] = [Palette.defaultAccent]

    var shelfMode: ShelfMode = ShelfMode(rawValue: UserDefaults.standard.string(forKey: "shelf") ?? "") ?? .recent {
        didSet {
            UserDefaults.standard.set(shelfMode.rawValue, forKey: "shelf")
            Task { await loadShelf() }
        }
    }
    var queue: [Tile] = []
    var recent: [Tile] = []
    var playlists: [Tile] = []

    var liked = false
    var opened: OpenCollection?
    var editable: [Tile] = []
    var toast: String?

    var searchText = ""
    var searchResults: [Tile] = []
    var searching = false

    var visibleSurfaces = 0 {
        didSet { if visibleSurfaces > oldValue { poke() } }
    }

    @ObservationIgnored private var progressMs = 0
    @ObservationIgnored private var progressStamp = Date()
    @ObservationIgnored private let auth = Auth()
    @ObservationIgnored private lazy var api = API(auth: auth)
    @ObservationIgnored let engine = Engine()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var wake: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var wakeGeneration = 0
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var holdUntil = Date.distantPast
    @ObservationIgnored private var volumeTask: Task<Void, Never>?
    @ObservationIgnored private var volumeQuietUntil = Date.distantPast
    @ObservationIgnored private var artURL: URL?
    @ObservationIgnored private var userID: String?

    var shelf: [Tile] {
        switch shelfMode {
        case .queue: queue
        case .recent: recent
        case .playlists: playlists
        }
    }

    var accentColor: Color { Color(nsColor: accent) }

    var artURL600: URL? { track?.artwork.best(near: 600) }

    func position(at date: Date = Date()) -> Int {
        guard isPlaying else { return progressMs }
        return min(durationMs, progressMs + Int(date.timeIntervalSince(progressStamp) * 1000))
    }

    func fraction(at date: Date = Date()) -> Double {
        Double(position(at: date)) / Double(max(durationMs, 1))
    }

    func boot() {
        engine.onChange = { [weak self] state in
            guard let self else { return }
            self.engineState = state
            if state == .running, self.phase == .needsEngineLogin { self.phase = .ready }
            self.poke()
        }
        engine.onLoginURL = { url in
            Browser.open(url)
        }
        DistributedNotificationCenter.default().addObserver(forName: Engine.eventNotification, object: nil, queue: .main) { [weak self] note in
            let event = note.object as? String ?? ""
            Task { @MainActor in self?.handleEngineEvent(event) }
        }
        Task {
            await resolvePhase()
            if phase == .needsSignIn, ProcessInfo.processInfo.environment["MEDTNER_URL_SINK"] != nil { await signIn() }
        }
    }

    func resolvePhase() async {
        if await auth.clientID == nil {
            phase = .needsClientID
        } else if await !auth.isSignedIn {
            phase = .needsSignIn
        } else {
            engine.start()
            phase = engine.hasCredentials ? .ready : .needsEngineLogin
            startLoop()
            await loadShelf()
            await loadEditable()
        }
    }

    func setClientID(_ id: String) async {
        UserDefaults.standard.set(id.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "clientID")
        await resolvePhase()
        if phase == .needsSignIn { await signIn() }
    }

    func signIn() async {
        do {
            try await auth.signIn()
            lastError = nil
        } catch {
            lastError = "Sign in didn't finish. Check the Client ID and redirect URI."
        }
        await resolvePhase()
    }

    func signOut() async {
        await auth.signOut()
        engine.resetLogin()
        loop?.cancel()
        loop = nil
        track = nil
        await resolvePhase()
    }

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                await self.sleep(self.nextInterval())
            }
        }
    }

    private func nextInterval() -> Double {
        let base: Double
        if visibleSurfaces > 0 {
            base = isPlaying ? 2.5 : 6
        } else {
            base = isPlaying ? 8 : 30
        }
        guard isPlaying else { return base }
        let remaining = Double(durationMs - position()) / 1000
        return max(0.4, min(base, remaining + 0.35))
    }

    private func sleep(_ seconds: Double) async {
        wakeGeneration += 1
        let generation = wakeGeneration
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            wake = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard let self, self.wakeGeneration == generation else { return }
                self.resumeWake()
            }
        }
    }

    private func resumeWake() {
        let continuation = wake
        wake = nil
        continuation?.resume()
    }

    func poke() {
        resumeWake()
    }

    private var onEngine: Bool { device == nil || device?.name == Engine.deviceName }

    private func handleEngineEvent(_ raw: String) {
        let parts = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let event = parts.first ?? ""
        if event == "volume_changed", let value = Int(parts.count > 1 ? parts[1] : ""), Date() > volumeQuietUntil {
            volume = Int((Double(value) / 65_535 * 100).rounded())
            engine.audio.setVolume(volume)
            UserDefaults.standard.set(volume, forKey: "engineVolume")
            return
        }
        if event == "playing" { engine.audio.release() }
        switch event {
        case "track_changed", "playing", "paused", "seeked", "stopped", "session_connected", "shuffle_changed":
            poke()
            if event == "track_changed" {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    await loadShelf()
                }
            }
        default:
            break
        }
    }

    func refresh() async {
        guard phase == .ready || phase == .needsEngineLogin else { return }
        do {
            let state = try await api.playback()
            guard Date() > holdUntil else { return }
            apply(state)
        } catch AuthError.denied {
            phase = .needsSignIn
        } catch {}
    }

    private func apply(_ state: PlaybackState?) {
        guard let state else {
            isPlaying = false
            device = nil
            return
        }
        let changed = state.item?.uri != track?.uri
        if changed {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { track = state.item }
            loadArtwork()
            liked = false
            if let uri = state.item?.uri {
                Task {
                    let result = (try? await api.libraryContains([uri]))?.first ?? false
                    if track?.uri == uri { liked = result }
                }
            }
            if shelfMode == .queue { Task { await loadShelf() } }
        }
        isPlaying = state.is_playing
        durationMs = max(state.item?.duration_ms ?? 1, 1)
        progressMs = state.progress_ms ?? 0
        progressStamp = Date()
        device = state.device
        shuffle = state.shuffle_state ?? false
        contextURI = state.context?.uri
        if state.device?.name != Engine.deviceName, let v = state.device?.volume_percent, volumeTask == nil, Date() > volumeQuietUntil {
            volume = v
        }
    }

    private func loadArtwork() {
        let url = track?.artwork.best(near: 600)
        guard url != artURL else { return }
        artURL = url
        guard let url else { return }
        Task {
            guard let image = await ArtworkStore.shared.image(url), url == artURL else { return }
            let colors = await Task.detached(priority: .utility) { Palette.palette(from: image) }.value
            let color = colors.first ?? Palette.defaultAccent
            artwork = image
            palette = colors
            withAnimation(.easeInOut(duration: 0.9)) { accent = color }
        }
    }

    private func engineDeviceID(wait seconds: Double) async -> String? {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if let list = try? await api.devices() {
                devices = list
                if let id = list.first(where: { $0.name == Engine.deviceName })?.id { return id }
            }
            try? await Task.sleep(for: .milliseconds(800))
        } while Date() < deadline
        return nil
    }

    private func hold(_ seconds: Double = 1.2) {
        holdUntil = Date().addingTimeInterval(seconds)
    }

    private func perform(_ action: @escaping (String?) async throws -> Void) {
        Task {
            do {
                try await action(nil)
            } catch APIError.noDevice {
                guard let id = await engineDeviceID(wait: 8) else {
                    lastError = "Medtner's speaker isn't ready yet."
                    return
                }
                try? await api.transfer(to: id, play: false)
                try? await Task.sleep(for: .milliseconds(400))
                try? await action(id)
            } catch {
                lastError = "\(error)"
            }
            try? await Task.sleep(for: .milliseconds(350))
            holdUntil = .distantPast
            await refresh()
        }
    }

    func togglePlay() {
        if device == nil {
            wakeAndResume()
            return
        }
        let wasPlaying = isPlaying
        progressMs = position()
        progressStamp = Date()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isPlaying.toggle() }
        if onEngine {
            if wasPlaying { engine.audio.hold() } else { engine.audio.release() }
        }
        hold()
        perform { [api] device in
            if wasPlaying { try await api.pause() } else { try await api.play(device: device) }
        }
    }

    private func wakeAndResume() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isPlaying = true }
        engine.audio.release()
        hold(2)
        Task {
            guard let id = await engineDeviceID(wait: 8) else {
                lastError = "Medtner's speaker isn't ready yet."
                isPlaying = false
                return
            }
            do {
                try await api.transfer(to: id, play: true)
            } catch {
                if let first = recent.first ?? playlists.first {
                    try? await api.play(device: id, context: first.contextURI, offset: first.contextURI == first.playURI ? nil : first.playURI)
                }
            }
            try? await Task.sleep(for: .milliseconds(600))
            holdUntil = .distantPast
            await refresh()
        }
    }

    func next() {
        hold(0.6)
        perform { [api] _ in try await api.next() }
    }

    func previous() {
        hold(0.6)
        perform { [api] _ in try await api.previous() }
    }

    func seek(to fraction: Double) {
        let ms = Int(Double(durationMs) * min(max(fraction, 0), 1))
        progressMs = ms
        progressStamp = Date()
        hold()
        perform { [api] _ in try await api.seek(ms) }
    }

    func setVolume(_ value: Int) {
        let clamped = min(max(value, 0), 100)
        volumeQuietUntil = Date().addingTimeInterval(2.5)
        guard clamped != volume || volumeTask == nil else { return }
        volume = clamped
        UserDefaults.standard.set(clamped, forKey: "engineVolume")
        engine.audio.setVolume(clamped)
        guard !onEngine, volumeTask == nil else { return }
        volumeTask = Task {
            var sent = -1
            while sent != volume {
                sent = volume
                try? await api.volume(sent)
                try? await Task.sleep(for: .milliseconds(90))
            }
            volumeTask = nil
        }
    }

    func toggleShuffle() {
        shuffle.toggle()
        let on = shuffle
        hold()
        perform { [api] _ in try await api.shuffle(on) }
    }

    func play(_ tile: Tile) {
        if onEngine { engine.audio.release() }
        hold(0.3)
        perform { [api] device in
            if let context = tile.contextURI {
                let offset = tile.playURI == context ? nil : tile.playURI
                try await api.play(device: device, context: context, offset: offset)
            } else {
                try await api.play(device: device, uris: [tile.playURI])
            }
        }
    }

    func playFromQueue(_ index: Int) {
        let count = index + 1
        hold(0.6)
        perform { [api] _ in
            for _ in 0..<count { try await api.next() }
        }
    }

    func enqueue(_ tile: Tile) {
        perform { [api] _ in try await api.addToQueue(tile.playURI) }
    }

    func transfer(to device: Device) {
        guard let id = device.id else { return }
        perform { [api] _ in try await api.transfer(to: id, play: true) }
    }

    func loadDevices() async {
        if let list = try? await api.devices() { devices = list }
    }

    func open(_ tile: Tile) {
        guard let context = tile.contextURI else { return play(tile) }
        if opened?.tile.id == tile.id { return closeCollection() }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { opened = OpenCollection(tile: tile) }
        Task {
            let parts = context.split(separator: ":").map(String.init)
            var tracks: [Track] = []
            var note: String?
            do {
                if parts.last == "collection" {
                    tracks = try await api.likedTracks()
                } else if parts.count == 3, parts[1] == "playlist" {
                    tracks = try await api.playlistTracks(parts[2])
                    if tracks.isEmpty { note = "Spotify only shares the songs in playlists you own. Press play to hear it." }
                } else if parts.count == 3, parts[1] == "album" {
                    tracks = try await api.albumTracks(parts[2])
                }
            } catch {
                note = "Spotify only shares the songs in playlists you own. Press play to hear it."
            }
            guard opened?.tile.id == tile.id else { return }
            let rows = tracks.enumerated().map { index, track in
                Tile(id: "\(index)-\(track.uri)", title: track.name, subtitle: track.artistLine,
                     art: track.artwork.best(near: 120) ?? tile.art, playURI: track.uri, contextURI: context)
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                opened?.tracks = rows
                opened?.loading = false
                opened?.note = note
            }
        }
    }

    func closeCollection() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { opened = nil }
    }

    func loadEditable() async {
        if userID == nil { userID = try? await api.me()?.id }
        guard let lists = try? await api.playlists() else { return }
        editable = lists
            .filter { $0.owner?.id == userID || $0.collaborative == true }
            .map { Tile(id: $0.id, title: $0.name, subtitle: "", art: nil, playURI: $0.uri, contextURI: $0.uri) }
    }

    func add(_ uri: String, to playlist: Tile) {
        Task {
            do {
                try await api.addToPlaylist(playlist.id, uris: [uri])
                flash("Added to \(playlist.title)")
            } catch {
                flash("Couldn't add to \(playlist.title)")
            }
        }
    }

    func unlike(_ uri: String) {
        if uri == track?.uri { withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { liked = false } }
        Task {
            do {
                try await api.removeFromLibrary([uri])
                flash("Removed from Liked Songs")
            } catch {
                if uri == track?.uri { liked = true }
                flash("Couldn't remove that one")
            }
        }
    }

    func like(_ uri: String) {
        if uri == track?.uri { withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { liked = true } }
        Task {
            do {
                try await api.saveToLibrary([uri])
                flash("Saved to Liked Songs")
            } catch {
                if uri == track?.uri { liked = false }
                flash("Couldn't save that one")
            }
        }
    }

    func queueUp(_ uri: String) {
        Task {
            do {
                try await api.addToQueue(uri)
                flash("Added to queue")
                if shelfMode == .queue { await loadShelf() }
            } catch {
                flash("Couldn't queue that one")
            }
        }
    }

    private func flash(_ message: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if toast == message { withAnimation(.easeOut(duration: 0.25)) { toast = nil } }
        }
    }

    func loadShelf() async {
        guard phase == .ready || phase == .needsEngineLogin else { return }
        switch shelfMode {
        case .queue:
            guard let tracks = try? await api.queue() else { return }
            var seen = Set<String>()
            queue = tracks.prefix(20).enumerated().compactMap { index, track in
                guard seen.insert(track.uri + "\(index)").inserted else { return nil }
                return Tile(id: "\(index)-\(track.uri)", title: track.name, subtitle: track.artistLine,
                            art: track.artwork.best(near: 200), playURI: track.uri, contextURI: nil)
            }
        case .recent:
            guard let items = try? await api.recent() else { return }
            var seen = Set<String>()
            recent = items.compactMap { item in
                let key = item.context?.uri ?? item.track.album?.uri ?? item.track.uri
                guard seen.insert(key).inserted else { return nil }
                return Tile(id: key, title: item.track.album?.name ?? item.track.name, subtitle: item.track.artistLine,
                            art: item.track.artwork.best(near: 200), playURI: item.track.uri,
                            contextURI: item.context?.uri ?? item.track.album?.uri)
            }
        case .playlists:
            guard let lists = try? await api.playlists() else { return }
            if userID == nil { userID = try? await api.me()?.id }
            var tiles: [Tile] = []
            if let userID {
                let liked = "spotify:user:\(userID):collection"
                tiles.append(Tile(id: liked, title: "Liked Songs", subtitle: "Your library", art: nil,
                                  playURI: liked, contextURI: liked, symbol: "heart.fill"))
            }
            tiles += lists.map {
                Tile(id: $0.uri, title: $0.name, subtitle: $0.owner?.display_name ?? "",
                     art: ($0.images ?? []).best(near: 200), playURI: $0.uri, contextURI: $0.uri)
            }
            playlists = tiles
        }
    }

    func search(_ text: String) {
        searchText = text
        searchTask?.cancel()
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let result = try? await api.search(query), !Task.isCancelled else { return }
            var tiles: [Tile] = []
            for track in (result.tracks?.items ?? []).compactMap({ $0 }) {
                tiles.append(Tile(id: track.uri, title: track.name, subtitle: track.artistLine,
                                  art: track.artwork.best(near: 120), playURI: track.uri, contextURI: track.album?.uri))
            }
            for album in (result.albums?.items ?? []).compactMap({ $0 }).prefix(4) {
                tiles.append(Tile(id: album.uri, title: album.name, subtitle: "Album · " + (album.artists?.first?.name ?? ""),
                                  art: album.images.best(near: 120), playURI: album.uri, contextURI: album.uri))
            }
            for list in (result.playlists?.items ?? []).compactMap({ $0 }).prefix(3) {
                tiles.append(Tile(id: list.uri, title: list.name, subtitle: "Playlist",
                                  art: (list.images ?? []).best(near: 120), playURI: list.uri, contextURI: list.uri))
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { searchResults = tiles }
        }
    }
}
