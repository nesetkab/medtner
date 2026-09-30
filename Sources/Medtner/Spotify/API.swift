import Foundation

enum APIError: Error {
    case status(Int, String)
    case noDevice
}

struct API {
    let auth: Auth
    private let base = URL(string: "https://api.spotify.com/v1")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    func playback() async throws -> PlaybackState? {
        try await get("me/player", query: ["additional_types": "track,episode"])
    }

    func devices() async throws -> [Device] {
        let response: DevicesResponse? = try await get("me/player/devices")
        return response?.devices ?? []
    }

    func queue() async throws -> [Track] {
        let response: QueueResponse? = try await get("me/player/queue")
        return response?.queue ?? []
    }

    func recent() async throws -> [RecentResponse.Item] {
        let response: RecentResponse? = try await get("me/player/recently-played", query: ["limit": "30"])
        return response?.items ?? []
    }

    func me() async throws -> Me? {
        try await get("me")
    }

    func playlists() async throws -> [Playlist] {
        let response: Paged<Playlist>? = try await get("me/playlists", query: ["limit": "40"])
        return response?.items.compactMap { $0 } ?? []
    }

    func search(_ text: String) async throws -> SearchResponse? {
        try await get("search", query: ["q": text, "type": "track,album,playlist", "limit": "10"])
    }

    func play(device: String?, context: String? = nil, uris: [String]? = nil, offset: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let context { body["context_uri"] = context }
        if let uris { body["uris"] = uris }
        if let offset { body["offset"] = ["uri": offset] }
        try await send("PUT", "me/player/play", query: device.map { ["device_id": $0] } ?? [:], body: body.isEmpty ? nil : body)
    }

    func pause() async throws { try await send("PUT", "me/player/pause") }
    func next() async throws { try await send("POST", "me/player/next") }
    func previous() async throws { try await send("POST", "me/player/previous") }

    func seek(_ ms: Int) async throws {
        try await send("PUT", "me/player/seek", query: ["position_ms": String(ms)])
    }

    func volume(_ percent: Int) async throws {
        try await send("PUT", "me/player/volume", query: ["volume_percent": String(percent)])
    }

    func shuffle(_ on: Bool) async throws {
        try await send("PUT", "me/player/shuffle", query: ["state": on ? "true" : "false"])
    }

    func addToQueue(_ uri: String) async throws {
        try await send("POST", "me/player/queue", query: ["uri": uri])
    }

    func transfer(to device: String, play: Bool) async throws {
        try await send("PUT", "me/player", body: ["device_ids": [device], "play": play])
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T? {
        let (data, status) = try await perform("GET", path, query: query, body: nil)
        if status == 204 || data.isEmpty { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func send(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws {
        _ = try await perform(method, path, query: query, body: body)
    }

    private func perform(_ method: String, _ path: String, query: [String: String], body: [String: Any]?) async throws -> (Data, Int) {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else if method != "GET" {
            request.setValue("0", forHTTPHeaderField: "Content-Length")
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404, String(data: data, encoding: .utf8)?.contains("NO_ACTIVE_DEVICE") == true {
            throw APIError.noDevice
        }
        guard (200..<300).contains(status) else {
            throw APIError.status(status, String(data: data, encoding: .utf8) ?? "")
        }
        return (data, status)
    }
}
