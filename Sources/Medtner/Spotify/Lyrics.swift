import Foundation

struct LyricLine: Identifiable, Hashable {
    let id: Int
    let time: Int
    let text: String
}

struct Lyrics: Equatable {
    let trackURI: String
    let lines: [LyricLine]
    let synced: Bool

    func index(at ms: Int) -> Int? {
        guard synced else { return nil }
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= ms {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }
}

enum LyricsSource {
    private struct Record: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let instrumental: Bool?
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.httpAdditionalHeaders = ["User-Agent": "Medtner (https://github.com/nesetkab/medtner)"]
        return URLSession(configuration: config)
    }()

    static func fetch(for track: Track) async -> Lyrics? {
        let artist = track.artists?.first?.name ?? track.artistLine
        var exact = URLComponents(string: "https://lrclib.net/api/get")!
        exact.queryItems = [
            .init(name: "track_name", value: track.name),
            .init(name: "artist_name", value: artist),
            .init(name: "album_name", value: track.album?.name ?? ""),
            .init(name: "duration", value: String(track.duration_ms / 1000)),
        ]
        if let record: Record = await load(exact.url), let lyrics = build(record, uri: track.uri) {
            return lyrics
        }
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [
            .init(name: "track_name", value: track.name),
            .init(name: "artist_name", value: artist),
        ]
        guard let records: [Record] = await load(search.url) else { return nil }
        let best = records.first { $0.syncedLyrics?.isEmpty == false } ?? records.first { $0.plainLyrics?.isEmpty == false }
        return best.flatMap { build($0, uri: track.uri) }
    }

    private static func load<T: Decodable>(_ url: URL?) async -> T? {
        guard let url, let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func build(_ record: Record, uri: String) -> Lyrics? {
        if let synced = record.syncedLyrics, !synced.isEmpty {
            let lines = parse(synced)
            if !lines.isEmpty { return Lyrics(trackURI: uri, lines: lines, synced: true) }
        }
        if let plain = record.plainLyrics, !plain.isEmpty {
            let lines = plain.components(separatedBy: .newlines).enumerated().map { LyricLine(id: $0, time: 0, text: $1) }
            return Lyrics(trackURI: uri, lines: lines, synced: false)
        }
        return nil
    }

    private static let stamp = try! NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#)

    private static func parse(_ lrc: String) -> [LyricLine] {
        var entries: [(Int, String)] = []
        for raw in lrc.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = stamp.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
            for match in matches {
                func group(_ i: Int) -> String? {
                    let r = match.range(at: i)
                    return r.location == NSNotFound ? nil : ns.substring(with: r)
                }
                let minutes = Int(group(1) ?? "") ?? 0
                let seconds = Int(group(2) ?? "") ?? 0
                let fraction = group(3) ?? "0"
                let millis = (Int(fraction) ?? 0) * (fraction.count == 1 ? 100 : fraction.count == 2 ? 10 : 1)
                entries.append(((minutes * 60 + seconds) * 1000 + millis, text))
            }
        }
        return entries.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(id: $0, time: $1.0, text: $1.1) }
    }
}
