import AppKit
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
    static let eventNotification = Notification.Name("app.medtner.engine.event")

    private(set) var state: State = .off {
        didSet { onChange?(state) }
    }
    var onChange: ((State) -> Void)?
    var onLoginURL: ((URL) -> Void)?

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

    func start() {
        guard process == nil else { return }
        guard let binary else {
            state = .missing
            return
        }
        killStale()

        let cache = Storage.directory.appendingPathComponent("engine", isDirectory: true)
        let audio = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Medtner/audio", isDirectory: true)
        let volume = UserDefaults.standard.object(forKey: "engineVolume") as? Int ?? 60

        var args = [
            "--name", Self.deviceName,
            "--device-type", "computer",
            "--bitrate", "320",
            "--system-cache", cache.path,
            "--cache", audio.path,
            "--cache-size-limit", "512M",
            "--disable-discovery",
            "--initial-volume", String(volume),
            "--volume-ctrl", "log",
            "--enable-volume-normalisation",
            "--autoplay", "on",
            "--quiet",
        ]
        if let hook = Bundle.main.executableURL {
            args += ["--onevent", hook.path]
        }
        if !hasCredentials {
            args += ["--enable-oauth", "--oauth-port", "5588"]
            args.removeAll { $0 == "--quiet" }
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["MEDTNER_HOOK"] = "1"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
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
            self.process = process
            startedAt = Date()
            try? String(process.processIdentifier).write(to: pidFile, atomically: true, encoding: .utf8)
            state = hasCredentials ? .running : .waitingForLogin
        } catch {
            state = .missing
        }
    }

    func stop() {
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

    static func handleHookInvocation() -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard env["MEDTNER_HOOK"] == "1" else { return false }
        guard let event = env["PLAYER_EVENT"] else { return true }
        DistributedNotificationCenter.default().postNotificationName(
            eventNotification,
            object: event,
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }
}
