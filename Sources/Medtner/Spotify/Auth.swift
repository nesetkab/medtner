import AppKit
import CryptoKit
import Foundation

struct Tokens: Codable {
    var access: String
    var refresh: String
    var expires: Date
    var scope: String?
}

enum AuthError: Error {
    case noClientID
    case denied
    case badResponse(String)
}

actor Auth {
    static let redirectPort: UInt16 = 8973
    static let redirectURI = "http://127.0.0.1:8973/callback"
    static let scopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "user-read-recently-played",
        "playlist-read-private",
        "playlist-read-collaborative",
        "playlist-modify-private",
        "playlist-modify-public",
        "user-library-read",
        "user-library-modify",
    ].joined(separator: " ")

    private var tokens: Tokens?
    private var refreshing: Task<Tokens, Error>?

    init() {
        tokens = Storage.load(Tokens.self, "tokens.json")
    }

    var clientID: String? {
        let id = UserDefaults.standard.string(forKey: "clientID")?.trimmingCharacters(in: .whitespaces)
        return (id?.isEmpty ?? true) ? nil : id
    }

    var isSignedIn: Bool {
        guard let granted = tokens?.scope?.split(separator: " ").map(String.init) else { return false }
        return Set(Self.scopes.split(separator: " ").map(String.init)).isSubset(of: granted)
    }

    func signOut() {
        tokens = nil
        Storage.remove("tokens.json")
    }

    func signIn() async throws {
        guard let clientID else { throw AuthError.noClientID }
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = Self.randomString(16)

        var url = URLComponents(string: "https://accounts.spotify.com/authorize")!
        url.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "state", value: state),
            .init(name: "scope", value: Self.scopes),
        ]

        let server = LoopbackServer()
        async let callback = server.waitForCode(port: Self.redirectPort, path: "/callback")
        let authorizeURL = url.url!
        await MainActor.run { Browser.open(authorizeURL) }
        let result = try await callback

        let items = result.queryItems ?? []
        guard
            items.first(where: { $0.name == "state" })?.value == state,
            let code = items.first(where: { $0.name == "code" })?.value
        else { throw AuthError.denied }

        tokens = try await requestTokens([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ], previousRefresh: nil)
    }

    func accessToken() async throws -> String {
        guard let current = tokens else { throw AuthError.denied }
        if current.expires.timeIntervalSinceNow > 60 { return current.access }
        if let refreshing { return try await refreshing.value.access }
        guard let clientID else { throw AuthError.noClientID }
        let task = Task {
            try await requestTokens([
                "grant_type": "refresh_token",
                "refresh_token": current.refresh,
                "client_id": clientID,
            ], previousRefresh: current.refresh)
        }
        refreshing = task
        defer { refreshing = nil }
        do {
            let fresh = try await task.value
            tokens = fresh
            return fresh.access
        } catch AuthError.badResponse(let message) where message.contains("invalid_grant") {
            signOut()
            throw AuthError.denied
        }
    }

    private func requestTokens(_ form: [String: String], previousRefresh: String?) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.formEncoded.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AuthError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }
        struct Body: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double
            let scope: String?
        }
        let body = try JSONDecoder().decode(Body.self, from: data)
        guard let refresh = body.refresh_token ?? previousRefresh else { throw AuthError.denied }
        let tokens = Tokens(access: body.access_token, refresh: refresh,
                            expires: Date().addingTimeInterval(body.expires_in), scope: body.scope ?? self.tokens?.scope)
        Storage.save(tokens, "tokens.json")
        return tokens
    }

    private static func randomString(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}

enum Storage {
    static let directory: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Medtner", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, _ name: String) {
        let url = directory.appendingPathComponent(name)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension Dictionary where Key == String, Value == String {
    var formEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }
}
