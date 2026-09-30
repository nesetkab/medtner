import AppKit
import MediaPlayer

@MainActor
final class NowPlaying {
    private let player: Player
    private let center = MPNowPlayingInfoCenter.default()
    private var trackURI: String?
    private var artworkSource: NSImage?

    init(player: Player) {
        self.player = player
        let commands = MPRemoteCommandCenter.shared()
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.player.togglePlay()
            return .success
        }
        commands.playCommand.addTarget { [weak self] _ in
            guard let self, !self.player.isPlaying else { return .success }
            self.player.togglePlay()
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.player.isPlaying else { return .success }
            self.player.togglePlay()
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            self?.player.next()
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            self?.player.previous()
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let duration = Double(self.player.durationMs) / 1000
            guard duration > 0 else { return .commandFailed }
            self.player.seek(to: event.positionTime / duration)
            return .success
        }
        observe()
    }

    private func observe() {
        withObservationTracking {
            publish()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func publish() {
        let track = player.track
        let playing = player.isPlaying
        let artwork = player.artwork
        _ = player.progressEpoch

        guard let track else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }

        var info = center.nowPlayingInfo ?? [:]
        if track.uri != trackURI {
            trackURI = track.uri
            artworkSource = nil
            info = [:]
            info[MPMediaItemPropertyTitle] = track.name
            info[MPMediaItemPropertyArtist] = track.artistLine
            if let album = track.album?.name { info[MPMediaItemPropertyAlbumTitle] = album }
        }
        if let artwork, artwork !== artworkSource {
            artworkSource = artwork
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        info[MPMediaItemPropertyPlaybackDuration] = Double(player.durationMs) / 1000
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(player.position()) / 1000
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        center.nowPlayingInfo = info
        center.playbackState = playing ? .playing : .paused
    }
}
