import AppKit

enum Browser {
    @MainActor
    static func open(_ url: URL) {
        if let sink = ProcessInfo.processInfo.environment["MEDTNER_URL_SINK"] {
            try? (url.absoluteString + "\n").write(toFile: sink, atomically: true, encoding: .utf8)
            return
        }
        NSWorkspace.shared.open(url)
    }
}
