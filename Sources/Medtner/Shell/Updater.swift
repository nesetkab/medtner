import AppKit
import Observation

@MainActor
@Observable
final class Updater {
    struct Release: Equatable {
        let version: String
        let download: URL
    }

    static let shared = Updater()
    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

    var available: Release?
    var checking = false
    var checkedOnce = false
    var installing = false

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let latest = URL(string: "https://api.github.com/repos/nesetkab/medtner/releases/latest")!

    func start() {
        Task {
            try? await Task.sleep(for: .seconds(15))
            await checkIfEnabled()
        }
        let timer = Timer(timeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkIfEnabled() }
        }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func checkIfEnabled() async {
        guard UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true else { return }
        await check()
    }

    func check() async {
        guard !checking else { return }
        checking = true
        defer {
            checking = false
            checkedOnce = true
        }
        struct Body: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let assets: [Asset]
        }
        var request = URLRequest(url: latest)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try? JSONDecoder().decode(Body.self, from: data),
              let asset = body.assets.first(where: { $0.name == "Medtner.zip" }) else { return }
        let version = body.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        available = Self.isNewer(version, than: Self.currentVersion) ? Release(version: version, download: asset.browser_download_url) : nil
    }

    func install() {
        guard let release = available, !installing else { return }
        installing = true
        Task {
            do {
                let (zip, _) = try await URLSession.shared.download(from: release.download)
                let staging = FileManager.default.temporaryDirectory.appendingPathComponent("medtner-update-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path])
                let fresh = staging.appendingPathComponent("Medtner.app")
                try Self.run("/usr/bin/codesign", ["--verify", "--deep", fresh.path])
                let target = Bundle.main.bundleURL.path
                let script = """
                while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
                rm -rf "\(target).new"
                /usr/bin/ditto "\(fresh.path)" "\(target).new" && rm -rf "\(target)" && mv "\(target).new" "\(target)"
                /usr/bin/xattr -dr com.apple.quarantine "\(target)" 2>/dev/null
                /usr/bin/open "\(target)"
                rm -rf "\(staging.path)"
                """
                let swap = Process()
                swap.executableURL = URL(fileURLWithPath: "/bin/sh")
                swap.arguments = ["-c", script]
                try swap.run()
                NSApp.terminate(nil)
            } catch {
                installing = false
            }
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
