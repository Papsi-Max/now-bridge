import XCTest
@testable import NowBridge

final class PlaybackReaderTests: XCTestCase {
    private func json(pos: Double = 10_000, cls: String = "pct player__action-pause pct-player-pause") -> String {
        """
        {"title":"Trop","artist":"Angèle","album":"Instinct","cover":"https://static.qobuz.com/c/abc_230.jpg",
         "pos":\(pos),"dur":180000,"playCls":"\(cls)"}
        """
    }

    func testNoPlayerWhenPageHasNoPlayer() {
        var r = PlaybackReader()
        XCTAssertEqual(r.read(#"{"noPlayer":true}"#), .noPlayer)
    }

    func testNoPlayerOnGarbage() {
        var r = PlaybackReader()
        XCTAssertEqual(r.read("not json"), .noPlayer)
    }

    func testIdleWhenPlayerHasNoTitle() {
        var r = PlaybackReader()
        XCTAssertEqual(r.read("{}"), .idle)
    }

    func testReadsTrackFields() {
        var r = PlaybackReader()
        guard case .track(let s) = r.read(json()) else { return XCTFail("expected a track") }
        XCTAssertEqual(s.track.title, "Trop")
        XCTAssertEqual(s.track.artist, "Angèle")
        XCTAssertEqual(s.track.album, "Instinct")
        XCTAssertEqual(s.track.duration, 180)
        XCTAssertEqual(s.position, 10)
        XCTAssertEqual(s.track.cover?.absoluteString, "https://static.qobuz.com/c/abc_600.jpg")
    }

    func testPlayingFromPauseButtonClass() {
        var r = PlaybackReader()
        guard case .track(let s) = r.read(json()) else { return XCTFail() }
        XCTAssertTrue(s.playing)
    }

    func testPausedFromPlayButtonClassOnceSeenPlaying() {
        var r = PlaybackReader()
        _ = r.read(json())
        guard case .track(let s) = r.read(json(cls: "pct player__action-play pct-player-play")) else { return XCTFail() }
        XCTAssertFalse(s.playing)
    }

    func testFallsBackOnPositionAdvanceWhenClassNeverSeen() {
        var r = PlaybackReader()
        let play = "pct player__action-play pct-player-play"
        guard case .track(let first) = r.read(json(pos: 10_000, cls: play)) else { return XCTFail() }
        XCTAssertFalse(first.playing)                       // no previous position yet
        guard case .track(let second) = r.read(json(pos: 11_000, cls: play)) else { return XCTFail() }
        XCTAssertTrue(second.playing)                       // position moved forward by 1 s
        guard case .track(let third) = r.read(json(pos: 11_000, cls: play)) else { return XCTFail() }
        XCTAssertFalse(third.playing)                       // position stopped
    }

    func testSeekJumpIsNotPlayback() {
        var r = PlaybackReader()
        let play = "pct player__action-play pct-player-play"
        _ = r.read(json(pos: 10_000, cls: play))
        guard case .track(let s) = r.read(json(pos: 90_000, cls: play)) else { return XCTFail() }
        XCTAssertFalse(s.playing)
    }

    func testResetForgetsPosition() {
        var r = PlaybackReader()
        let play = "pct player__action-play pct-player-play"
        _ = r.read(json(pos: 10_000, cls: play))
        r.reset()
        guard case .track(let s) = r.read(json(pos: 11_000, cls: play)) else { return XCTFail() }
        XCTAssertFalse(s.playing)
    }
}

final class HelpersTests: XCTestCase {
    func testUpscaledCover() {
        XCTAssertEqual(upscaledCover("https://x/y_230.jpg")?.absoluteString, "https://x/y_600.jpg")
        XCTAssertEqual(upscaledCover("https://x/y.jpg")?.absoluteString, "https://x/y.jpg")
    }

    func testMenuBarTextTruncates() {
        XCTAssertEqual(menuBarText("short"), "short")
        let long = String(repeating: "a", count: 60)
        XCTAssertEqual(menuBarText(long).count, 40)
        XCTAssertTrue(menuBarText(long).hasSuffix("…"))
    }

    func testPortValidation() {
        XCTAssertEqual(Prefs.validPort(9222), 9222)
        XCTAssertEqual(Prefs.validPort(1024), 1024)
        XCTAssertEqual(Prefs.validPort(65535), 65535)
        XCTAssertEqual(Prefs.validPort(0), Prefs.defaultPort)
        XCTAssertEqual(Prefs.validPort(80), Prefs.defaultPort)
        XCTAssertEqual(Prefs.validPort(70_000), Prefs.defaultPort)
    }
}

final class ConnectionTests: XCTestCase {
    private let now = Date()

    private func state(_ status: BridgeState.Status, age: TimeInterval = 1, playing: Bool = true) -> BridgeState {
        BridgeState(status: status, title: "Trop", artist: "Angèle", playing: playing, updated: now.addingTimeInterval(-age))
    }

    private func derive(running: Bool = true, reachable: Bool = true, _ s: BridgeState?) -> Connection {
        .derive(qobuzRunning: running, portReachable: reachable, state: s, now: now)
    }

    func testQobuzClosed() { XCTAssertEqual(derive(running: false, state(.connected)), .qobuzClosed) }
    func testPortInactive() { XCTAssertEqual(derive(reachable: false, state(.connected)), .portInactive) }
    func testStartingWithoutState() { XCTAssertEqual(derive(nil), .starting) }
    func testStaleStateIsStarting() { XCTAssertEqual(derive(state(.connected, age: 30)), .starting) }
    func testConnectedText() { XCTAssertEqual(derive(state(.connected)), .connected(text: "Trop — Angèle", playing: true)) }
    func testIdle() { XCTAssertEqual(derive(state(.idle)), .idle) }
    func testNoPlayer() { XCTAssertEqual(derive(state(.noPlayer)), .noPlayer) }
    func testUnreachableMapsToPortInactive() { XCTAssertEqual(derive(state(.unreachable)), .portInactive) }

    func testHealth() {
        XCTAssertEqual(Connection.idle.isHealthy, true)
        XCTAssertEqual(Connection.portInactive.isHealthy, false)
        XCTAssertNil(Connection.qobuzClosed.isHealthy)
    }

    func testLabelDistinguishesPlayingAndPaused() {
        XCTAssertEqual(Connection.connected(text: "A", playing: true).label, "Playing: A")
        XCTAssertEqual(Connection.connected(text: "A", playing: false).label, "Paused: A")
    }
}

final class StateFileTests: XCTestCase {
    func testRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let state = BridgeState(status: .connected, title: "Trop", artist: "Angèle", album: "Instinct",
                                playing: true, updated: Date(timeIntervalSince1970: 1_700_000_000))
        StateFile.write(state, to: url)
        let read = try XCTUnwrap(StateFile.read(from: url))
        XCTAssertEqual(read.status, .connected)
        XCTAssertEqual(read.title, "Trop")
        XCTAssertEqual(read.artist, "Angèle")
        XCTAssertTrue(read.playing)
        XCTAssertEqual(read.updated.timeIntervalSince1970, 1_700_000_000, accuracy: 1)
    }

    func testMissingFileReadsNil() {
        XCTAssertNil(StateFile.read(from: URL(fileURLWithPath: "/nonexistent/state.json")))
    }
}
