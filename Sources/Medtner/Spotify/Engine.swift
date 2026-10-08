import AppKit
import CryptoKit
import Foundation

@MainActor
final class Engine {
    enum State: Equatable {
        case off
        case missing
        case waitingForLogin
        case running
    }

    static let deviceName = "Medtner"
    static let deviceID = Insecure.SHA1.hash(data: Data(deviceName.utf8)).map { String(format: "%02x", $0) }.joined()
    nonisolated static let eventNotification = Notification.Name("app.medtner.engine.event")

    private(set) var state: State = .off {
        didSet { onChange?(state) }
    }
    var onChange: ((State) -> Void)?
    var onLoginURL: ((URL) -> Void)?
    var onEvent: ((String) -> Void)?
    var onTrack: ((Track) -> Void)?
    private var builtin = false
    private var bridge: EngineBridge?
    private var retiring: [EngineBridge] = []
    private var startWhenRetired = false

    let audio = AudioOut()
    private var process: Process?
    private var restarts = 0
    private var startedAt = Date()
    private var buffer = ""
    private let pidFile = Storage.directory.appendingPathComponent("engine.pid")

    var binary: URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("librespot")
        let candidates = [bundled?.path, "/opt/homebrew/bin/librespot", "/usr/local/bin/librespot"].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    var hasCredentials: Bool {
        FileManager.default.fileExists(atPath: Storage.directory.appendingPathComponent("engine/credentials.json").path)
    }

    var useBuiltin: Bool {
        !(UserDefaults.standard.bool(forKey: "externalEngine"))
    }

    func start() {
        guard process == nil, !builtin else { return }
        if !retiring.isEmpty {
            startWhenRetired = true
            return
        }
        if useBuiltin {
            startBuiltin()
            return
        }
        startExternal()
    }

    private func startBuiltin() {
        let cache = Storage.directory.appendingPathComponent("engine", isDirectory: true)
        let audioCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Medtner/audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: audioCache, withIntermediateDirectories: true)
        killStale()
        let volume = UserDefaults.standard.object(forKey: "engineVolume") as? Int ?? 60
        audio.setVolume(volume)

        let bridge = EngineBridge(audio: audio) { [weak self] source, name, value, at in
            self?.handleBuiltin(from: source, name, value, at: at)
        }
        self.bridge = bridge
        let context = Unmanaged.passUnretained(bridge).toOpaque()
        let logPath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Medtner/engine.log").path
        let started = Self.deviceName.withCString { name in
            logPath.withCString { log in
            cache.path.withCString { system in
                audioCache.path.withCString { audioPath in
                    var config = MedtnerEngineConfig(
                        name: name,
                        log_path: log,
                        system_cache: system,
                        audio_cache: audioPath,
                        audio_cache_limit: 512 * 1024 * 1024,
                        bitrate: UInt32(UserDefaults.standard.object(forKey: "bitrate") as? Int ?? 320),
                        normalize: UserDefaults.standard.object(forKey: "normalize") as? Bool ?? true,
                        initial_volume: UInt32(volume),
                        autoplay: UserDefaults.standard.object(forKey: "autoplay") as? Bool ?? true,
                        audio: { context, samples, count in
                            guard let context, let samples else { return }
                            Unmanaged<EngineBridge>.fromOpaque(context).takeUnretainedValue().audio.push(samples, count: count)
                        },
                        event: { context, event, value in
                            guard let context, let event else { return }
                            let name = String(cString: event)
                            let bridge = Unmanaged<EngineBridge>.fromOpaque(context).takeUnretainedValue()
                            let at = Date().timeIntervalSince1970
                            bridge.react(to: name)
                            DispatchQueue.main.async { bridge.handle(name, value, at: at) }
                        },
                        context: context
                    )
                    return medtner_engine_start(&config)
                }
            }
            }
        }
        guard started else {
            self.bridge = nil
            startExternal()
            return
        }
        builtin = true
        state = hasCredentials ? .running : .waitingForLogin
    }

    private struct EngineTrack: Decodable {
        let uri: String
        let name: String
        let artists: [String]
        let album: String
        let duration_ms: Int
        let cover: String
    }

    private func handleBuiltin(from source: EngineBridge, _ name: String, _ value: Int64, at: TimeInterval) {
        if name == "exited" {
            retire(source)
            return
        }
        guard source === bridge else { return }
        if name.hasPrefix("track_info:") {
            guard let data = name.dropFirst("track_info:".count).data(using: .utf8),
                  let info = try? JSONDecoder().decode(EngineTrack.self, from: data) else { return }
            let images = info.cover.isEmpty ? [] : [SpotifyImage(url: info.cover, width: 640)]
            let track = Track(id: info.uri.split(separator: ":").last.map(String.init), uri: info.uri, name: info.name,
                              duration_ms: info.duration_ms, artists: info.artists.map { Artist(name: $0, uri: nil) },
                              album: Album(name: info.album, uri: "", images: images, artists: nil), images: nil, show: nil)
            onTrack?(track)
            return
        }
        switch name {
        case "needs_login":
            state = .waitingForLogin
        case "running":
            state = .running
        case "failed":
            state = .off
        case "reconnecting", "sink_started", "sink_stopped":
            break
        default:
            onEvent?("\(name)|\(value)|\(at)")
        }
    }

    private func retire(_ source: EngineBridge) {
        retiring.removeAll { $0 === source }
        if source === bridge {
            bridge = nil
            builtin = false
            state = .off
        }
        if startWhenRetired, retiring.isEmpty {
            startWhenRetired = false
            start()
        }
    }

    private func startExternal() {
        guard process == nil else { return }
        guard let binary else {
            state = .missing
            return
        }
        killStale()

        let cache = Storage.directory.appendingPathComponent("engine", isDirectory: true)
        let audioCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Medtner/audio", isDirectory: true)
        let volume = UserDefaults.standard.object(forKey: "engineVolume") as? Int ?? 60

        var args = [
            "--name", Self.deviceName,
            "--device-type", "computer",
            "--bitrate", String(UserDefaults.standard.object(forKey: "bitrate") as? Int ?? 320),
            "--system-cache", cache.path,
            "--cache", audioCache.path,
            "--cache-size-limit", "512M",
            "--disable-discovery",
            "--initial-volume", String(volume),
            "--volume-ctrl", "fixed",
            "--backend", "pipe",
            "--format", "S16",
            "--autoplay", "on",
            "--quiet",
        ]
        if UserDefaults.standard.object(forKey: "normalize") as? Bool ?? true {
            args.append("--enable-volume-normalisation")
        }
        if let hook = Bundle.main.url(forAuxiliaryExecutable: "medtner-hook") ?? Bundle.main.executableURL {
            args += ["--onevent", hook.path]
        }
        if !hasCredentials {
            args += ["--enable-oauth", "--oauth-port", "5588"]
            args.removeAll { $0 == "--quiet" }
        }

        let process = Process()
        process.qualityOfService = .userInteractive
        process.executableURL = binary
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["MEDTNER_HOOK"] = "1"
        process.environment = env

        var fds: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else {
            state = .missing
            return
        }
        var size: Int32 = 8_192
        setsockopt(fds[1], SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fds[0], SOL_SOCKET, SO_RCVBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        let audioWrite = FileHandle(fileDescriptor: fds[1], closeOnDealloc: true)
        let audioRead = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true)
        audio.setVolume(volume)

        let pipe = Pipe()
        process.standardOutput = audioWrite
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.consume(text) }
        }

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in self?.handleExit(proc) }
        }

        do {
            try process.run()
            try? audioWrite.close()
            audio.stream(from: audioRead)
            self.process = process
            startedAt = Date()
            try? String(process.processIdentifier).write(to: pidFile, atomically: true, encoding: .utf8)
            state = hasCredentials ? .running : .waitingForLogin
        } catch {
            state = .missing
        }
    }

    func radio(_ trackURI: String) -> Bool {
        guard builtin else { return false }
        return trackURI.withCString { medtner_engine_radio($0) }
    }

    func next() -> Bool { builtin && medtner_engine_next() }
    func previous() -> Bool { builtin && medtner_engine_previous() }
    func seek(_ ms: Int) -> Bool { builtin && medtner_engine_seek(UInt32(max(ms, 0))) }

    func restart() {
        stop()
        restarts = 0
        start()
    }

    func stop() {
        if builtin {
            medtner_engine_stop()
            if let bridge { retiring.append(bridge) }
            bridge = nil
            builtin = false
            state = .off
            return
        }
        guard let process else { return }
        process.terminationHandler = nil
        process.terminate()
        self.process = nil
        try? FileManager.default.removeItem(at: pidFile)
        state = .off
    }

    func resetLogin() {
        stop()
        try? FileManager.default.removeItem(at: Storage.directory.appendingPathComponent("engine/credentials.json"))
    }

    private func consume(_ text: String) {
        buffer += text
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)
            if let urlRange = line.range(of: "Browse to: "), let url = URL(string: String(line[urlRange.upperBound...]).trimmingCharacters(in: .whitespaces)) {
                onLoginURL?(url)
            }
            if line.contains("Authenticated as") || line.contains("Using cached credentials") {
                state = .running
            }
        }
        if buffer.count > 8_000 { buffer = "" }
    }

    private func handleExit(_ proc: Process) {
        process = nil
        try? FileManager.default.removeItem(at: pidFile)
        if Date().timeIntervalSince(startedAt) > 60 { restarts = 0 }
        guard restarts < 5 else {
            state = .off
            return
        }
        restarts += 1
        let delay = Double(restarts) * 1.5
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            self.start()
        }
    }

    private func killStale() {
        guard
            let text = try? String(contentsOf: pidFile, encoding: .utf8),
            let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return }
        kill(pid, SIGTERM)
        try? FileManager.default.removeItem(at: pidFile)
    }

    nonisolated static func handleHookInvocation() -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard env["MEDTNER_HOOK"] == "1" else { return false }
        guard let event = env["PLAYER_EVENT"] else { return true }
        DistributedNotificationCenter.default().postNotificationName(
            eventNotification,
            object: event + "|" + (env["VOLUME"] ?? ""),
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }
}

final class EngineBridge: @unchecked Sendable {
    let audio: AudioOut
    private let onEvent: @MainActor (EngineBridge, String, Int64, TimeInterval) -> Void

    init(audio: AudioOut, onEvent: @escaping @MainActor (EngineBridge, String, Int64, TimeInterval) -> Void) {
        self.audio = audio
        self.onEvent = onEvent
    }

    func react(to name: String) {
        switch name {
        case "seeked": audio.seeked()
        case "track_changed", "playing": audio.openGate()
        default: break
        }
    }

    @MainActor
    func handle(_ name: String, _ value: Int64, at: TimeInterval) {
        onEvent(self, name, value, at)
    }
}
