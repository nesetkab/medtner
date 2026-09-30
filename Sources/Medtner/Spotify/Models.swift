import Foundation

struct SpotifyImage: Codable, Hashable {
    let url: String
    let width: Int?
}

extension Array where Element == SpotifyImage {
    func best(near size: Int) -> URL? {
        let sorted = self.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        let pick = sorted.first { ($0.width ?? 0) >= size } ?? sorted.last
        return pick.flatMap { URL(string: $0.url) }
    }
}

struct Artist: Codable, Hashable {
    let name: String
    let uri: String?
}

struct Album: Codable, Hashable {
    let name: String
    let uri: String
    let images: [SpotifyImage]
    let artists: [Artist]?
}

struct Track: Codable, Hashable, Identifiable {
    let id: String?
    let uri: String
    let name: String
    let duration_ms: Int
    let artists: [Artist]?
    let album: Album?
    let images: [SpotifyImage]?
    let show: Show?

    struct Show: Codable, Hashable {
        let name: String
        let images: [SpotifyImage]
    }

    var artistLine: String {
        if let artists, !artists.isEmpty { return artists.map(\.name).joined(separator: ", ") }
        return show?.name ?? ""
    }

    var artwork: [SpotifyImage] {
        album?.images ?? images ?? show?.images ?? []
    }
}

struct Device: Codable, Hashable, Identifiable {
    let id: String?
    let name: String
    let type: String
    let is_active: Bool
    let volume_percent: Int?
    let supports_volume: Bool?
}

struct PlaybackContext: Codable, Hashable {
    let uri: String
    let type: String
}

struct PlaybackState: Codable {
    let device: Device?
    let shuffle_state: Bool?
    let repeat_state: String?
    let progress_ms: Int?
    let is_playing: Bool
    let item: Track?
    let context: PlaybackContext?
}

struct QueueResponse: Codable {
    let currently_playing: Track?
    let queue: [Track]
}

struct RecentResponse: Codable {
    struct Item: Codable {
        let track: Track
        let context: PlaybackContext?
    }
    let items: [Item]
}

struct Paged<T: Codable>: Codable {
    let items: [T?]
}

struct Playlist: Codable, Hashable {
    let id: String
    let name: String
    let uri: String
    let images: [SpotifyImage]?
    let owner: Owner?

    struct Owner: Codable, Hashable {
        let display_name: String?
    }
}

struct SearchResponse: Codable {
    let tracks: Paged<Track>?
    let albums: Paged<Album>?
    let playlists: Paged<Playlist>?
}

struct DevicesResponse: Codable {
    let devices: [Device]
}

struct Tile: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let art: URL?
    let playURI: String
    let contextURI: String?
    var symbol: String? = nil
}

struct Me: Codable {
    let id: String
}
