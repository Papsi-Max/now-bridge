import Foundation

/// What the page showed at one poll.
enum Reading: Equatable {
    case noPlayer          // the page is there but not the player (signed out, interface changed…)
    case idle              // player present, no track loaded
    case track(Snapshot)
}

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var cover: URL?
    var duration: Double
}

struct Snapshot: Equatable {
    var track: Track
    var position: Double
    var playing: Bool
}

/// Turns the JSON returned by `readJS` into a `Reading`, and works out whether music is playing.
struct PlaybackReader {
    private var lastPosition = -1.0
    private var sawPauseClass = false

    mutating func reset() { lastPosition = -1 }

    mutating func read(_ json: String) -> Reading {
        guard let d = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return .noPlayer }
        if d["noPlayer"] as? Bool == true { return .noPlayer }
        guard let title = d["title"] as? String else { return .idle }

        let position = (d["pos"] as? Double ?? 0) / 1000
        // The central button becomes "pause" while playing; if we never saw that, fall back on the position advancing.
        let byClass = (d["playCls"] as? String ?? "").contains("pct-player-pause")
        if byClass { sawPauseClass = true }
        let advancing = lastPosition >= 0 && position > lastPosition && position - lastPosition < 3
        lastPosition = position

        let track = Track(title: title, artist: d["artist"] as? String ?? "", album: d["album"] as? String ?? "",
                          cover: (d["cover"] as? String).flatMap(upscaledCover),
                          duration: (d["dur"] as? Double ?? 0) / 1000)
        return .track(Snapshot(track: track, position: position, playing: sawPauseClass ? byClass : advancing))
    }
}

/// Qobuz serves 230 px thumbnails; the 600 px version has the same URL with a different suffix.
func upscaledCover(_ url: String) -> URL? {
    URL(string: url.replacingOccurrences(of: "_230.", with: "_600."))
}

func menuBarText(_ text: String, limit: Int = 40) -> String {
    text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
}

enum Connection: Equatable {
    case qobuzClosed, starting, portInactive, noPlayer, idle
    case connected(text: String, playing: Bool)

    var label: String {
        switch self {
        case .qobuzClosed: "Qobuz is not running"
        case .starting: "Connecting…"
        case .portInactive: "Qobuz is open without the debug port"
        case .noPlayer: "Player not found (signed out, or Qobuz interface changed)"
        case .idle: "Connected, nothing playing"
        case .connected(let text, let playing): "\(playing ? "Playing" : "Paused"): \(text)"
        }
    }

    /// nil while the situation is still settling.
    var isHealthy: Bool? {
        switch self {
        case .connected, .idle: true
        case .qobuzClosed, .starting: nil
        case .portInactive, .noPlayer: false
        }
    }

    /// A state file older than this means the player process stopped reporting.
    static let staleAfter: TimeInterval = 8

    static func derive(qobuzRunning: Bool, portReachable: Bool, state: BridgeState?, now: Date = Date()) -> Connection {
        guard qobuzRunning else { return .qobuzClosed }
        guard portReachable else { return .portInactive }
        guard let s = state, now.timeIntervalSince(s.updated) < staleAfter else { return .starting }
        switch s.status {
        case .connected:
            return .connected(text: [s.title, s.artist].filter { !$0.isEmpty }.joined(separator: " — "), playing: s.playing)
        case .idle: return .idle
        case .noPlayer: return .noPlayer
        case .unreachable: return .portInactive
        }
    }
}
