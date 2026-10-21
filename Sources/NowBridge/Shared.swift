import Foundation

/// Settings shared by the main process and the player child process (same UserDefaults domain).
enum Prefs {
    static let qobuzID = "com.qobuz.desktop"
    static let defaultPort = 9222

    static func register() {
        UserDefaults.standard.register(defaults: [
            "showIcon": true, "showTitle": false,
            "autoRelaunch": true, "launchQobuzAtStart": false,
            "silent": false, "port": defaultPort,
        ])
    }

    static var port: Int { validPort(UserDefaults.standard.integer(forKey: "port")) }

    /// Falls back to the default for anything outside the unprivileged port range.
    static func validPort(_ p: Int) -> Int { (1024...65535).contains(p) ? p : defaultPort }
    static var showIcon: Bool { UserDefaults.standard.bool(forKey: "showIcon") }
    static var showTitle: Bool { UserDefaults.standard.bool(forKey: "showTitle") }
    static var autoRelaunch: Bool { UserDefaults.standard.bool(forKey: "autoRelaunch") }
    static var launchQobuzAtStart: Bool { UserDefaults.standard.bool(forKey: "launchQobuzAtStart") }
    static var silent: Bool { UserDefaults.standard.bool(forKey: "silent") }
}

/// State written by the player process and read by the main process (menu, settings).
struct BridgeState: Codable {
    enum Status: String, Codable { case connected, idle, noPlayer, unreachable }
    var status: Status
    var title = ""
    var artist = ""
    var album = ""
    var playing = false
    var updated = Date()
}

enum StateFile {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NowBridge/state.json")
    }

    static func write(_ state: BridgeState, to url: URL = StateFile.url) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? enc.encode(state) { try? data.write(to: url, options: .atomic) }
    }

    static func read(from url: URL = StateFile.url) -> BridgeState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(BridgeState.self, from: data)
    }
}

/// Does Qobuz's debug port answer?
func debugPortReachable() async -> Bool {
    var req = URLRequest(url: URL(string: "http://127.0.0.1:\(Prefs.port)/json/version")!)
    req.timeoutInterval = 1
    return (try? await URLSession.shared.data(for: req)) != nil
}
