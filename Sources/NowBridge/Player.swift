import AppKit
import AVFoundation
import MediaPlayer

let readJS = """
(() => {
  const q = s => document.querySelector(s);
  if (!q('.player')) return JSON.stringify({ noPlayer: true });
  const title = q('.player__track-name .player__track-overflow')?.textContent?.trim();
  if (!title) return JSON.stringify({});
  const pr = q('.player progress');
  return JSON.stringify({
    title,
    artist: q('.player__track-album a[href^="/artist"]')?.textContent ?? '',
    album: q('.player__track-album a[href^="/album"]')?.textContent ?? '',
    cover: q('.player__track-cover img')?.src ?? '',
    pos: Number(pr?.value ?? 0), dur: Number(pr?.max ?? 0),
    playCls: q('.player__action-play, .player__action-pause')?.className ?? ''
  });
})()
"""

/// Child process: the only one talking to Now Playing. It only lives while Qobuz is open,
/// because macOS keeps an app as a "player" for as long as its process exists.
@MainActor
final class Player: NSObject, NSApplicationDelegate {
    let cdp = CDP()
    var silentPlayer: AVAudioPlayer?

    var lastTrack: Track?
    var lastPlaying = false
    var reader = PlaybackReader()
    var lastPublished: (pos: Double, at: Date)?
    var artwork: MPMediaItemArtwork?
    var commandsEnabled = true
    var lastReport: (state: BridgeState, at: Date)?

    func applicationDidFinishLaunching(_ n: Notification) {
        setupRemoteCommands()
        if Prefs.silent { setSilent(true) }
        clearNowPlaying()
        Task { await pollLoop() }
    }

    // MARK: reading state

    func pollLoop() async {
        while true {
            if getppid() == 1 { exit(0) }
            do {
                let json = try await cdp.eval(readJS)
                handle(json.map { reader.read($0) } ?? .noPlayer)
            } catch {
                clearNowPlaying()
                report(BridgeState(status: .unreachable))
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    func handle(_ reading: Reading) {
        switch reading {
        case .noPlayer:
            reader.reset(); clearNowPlaying(); report(BridgeState(status: .noPlayer))
        case .idle:
            reader.reset(); clearNowPlaying(); report(BridgeState(status: .idle))
        case .track(let s):
            apply(s)
            report(BridgeState(status: .connected, title: s.track.title, artist: s.track.artist,
                               album: s.track.album, playing: s.playing))
        }
    }

    /// Writes the state for the main process: on every change, otherwise every 3 s (heartbeat).
    func report(_ state: BridgeState) {
        if let last = lastReport, last.state.status == state.status, last.state.title == state.title,
           last.state.playing == state.playing, Date().timeIntervalSince(last.at) < 3 { return }
        lastReport = (state, Date())
        StateFile.write(state)
    }

    // MARK: publishing to macOS

    func apply(_ s: Snapshot) {
        let changed = s.track != lastTrack || s.playing != lastPlaying
        let expected = lastPublished.map { $0.pos + (lastPlaying ? Date().timeIntervalSince($0.at) : 0) } ?? -99
        let drifted = abs(expected - s.position) > 1.5
        guard changed || drifted else { return }

        if s.track != lastTrack { artwork = nil; loadArtwork(for: s.track) }
        lastTrack = s.track; lastPlaying = s.playing
        lastPublished = (s.position, Date())
        publish(s)
    }

    func publish(_ s: Snapshot) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: s.track.title,
            MPMediaItemPropertyArtist: s.track.artist,
            MPMediaItemPropertyAlbumTitle: s.track.album,
            MPMediaItemPropertyPlaybackDuration: s.track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: s.position,
            MPNowPlayingInfoPropertyPlaybackRate: s.playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        if !commandsEnabled { setCommandsEnabled(true) }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = s.playing ? .playing : .paused
    }

    /// With no track, the app withdraws from Now Playing: no info, stopped state, commands disabled.
    func clearNowPlaying() {
        guard lastTrack != nil || commandsEnabled else { return }
        lastTrack = nil; lastPublished = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        setCommandsEnabled(false)
    }

    func setCommandsEnabled(_ on: Bool) {
        commandsEnabled = on
        let rc = MPRemoteCommandCenter.shared()
        for c in [rc.playCommand, rc.pauseCommand, rc.togglePlayPauseCommand, rc.nextTrackCommand, rc.previousTrackCommand] {
            c.isEnabled = on
        }
    }

    func loadArtwork(for track: Track) {
        guard let url = track.cover else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let img = NSImage(data: data) else { return }
            let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            await MainActor.run {
                guard self.lastTrack == track else { return }
                self.artwork = art
                MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = art
            }
        }
    }

    // MARK: commands to Qobuz

    func click(_ selector: String) {
        Task { _ = try? await cdp.eval("document.querySelector('\(selector)')?.click()") }
    }

    func setupRemoteCommands() {
        let rc = MPRemoteCommandCenter.shared()
        func bind(_ cmd: MPRemoteCommand, _ selector: String, when: ((Player) -> Bool)? = nil) {
            cmd.isEnabled = true
            cmd.addTarget { [weak self] _ in
                guard let self else { return .commandFailed }
                if let when, !when(self) { return .success }   // already in the requested state
                Task { @MainActor in self.click(selector) }
                return .success
            }
        }
        bind(rc.playCommand, ".player__action-play", when: { !$0.lastPlaying })
        bind(rc.pauseCommand, ".player__action-pause", when: { $0.lastPlaying })
        bind(rc.togglePlayPauseCommand, ".player__action-play, .player__action-pause")
        bind(rc.nextTrackCommand, ".player__action-next")
        bind(rc.previousTrackCommand, ".player__action-previous")
    }

    // MARK: silent audio

    func setSilent(_ on: Bool) {
        guard on else { silentPlayer?.stop(); silentPlayer = nil; return }
        // 1 s of 16-bit mono PCM silence, looped
        let rate = 8000, n = rate
        var wav = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        wav.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + n * 2)); wav.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        wav.append("data".data(using: .ascii)!); u32(UInt32(n * 2)); wav.append(Data(count: n * 2))
        silentPlayer = try? AVAudioPlayer(data: wav)
        silentPlayer?.numberOfLoops = -1
        silentPlayer?.volume = 0.01
        silentPlayer?.play()
    }
}
