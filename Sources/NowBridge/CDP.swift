import Foundation

/// Minimal Chrome DevTools Protocol client (Runtime.evaluate) for Qobuz.
/// Only talks to 127.0.0.1: Qobuz must be launched with --remote-debugging-port.
actor CDP {
    static var port: Int { Prefs.port }

    private var task: URLSessionWebSocketTask?
    private var nextID = 0
    private var waiters: [Int: CheckedContinuation<String?, Error>] = [:]

    struct Failure: Error { let message: String }

    private func connect() async throws {
        let url = URL(string: "http://127.0.0.1:\(Self.port)/json/list")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        let (data, _) = try await URLSession.shared.data(for: req)
        let targets = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        guard let ws = targets.first(where: { ($0["url"] as? String)?.hasSuffix("app.html") == true })?["webSocketDebuggerUrl"] as? String,
              let wsURL = URL(string: ws) else { throw Failure(message: "Qobuz page not found") }
        let t = URLSession.shared.webSocketTask(with: wsURL)
        t.resume()
        task = t
        Task { await self.receiveLoop(t) }
    }

    private func receiveLoop(_ t: URLSessionWebSocketTask) async {
        while true {
            do {
                let msg = try await t.receive()
                guard case .string(let s) = msg,
                      let obj = try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any],
                      let id = obj["id"] as? Int, let c = waiters.removeValue(forKey: id) else { continue }
                let value = ((obj["result"] as? [String: Any])?["result"] as? [String: Any])?["value"] as? String
                c.resume(returning: value)
            } catch {
                drop(error)
                return
            }
        }
    }

    private func drop(_ error: Error) {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        let w = waiters
        waiters = [:]
        for (_, c) in w { c.resume(throwing: error) }
    }

    /// Evaluates JS in the page and returns its value (a string, typically JSON).
    func eval(_ expression: String) async throws -> String? {
        if task == nil { try await connect() }
        nextID += 1
        let id = nextID
        let payload: [String: Any] = ["id": id, "method": "Runtime.evaluate",
                                      "params": ["expression": expression, "returnByValue": true]]
        let text = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        return try await withCheckedThrowingContinuation { cont in
            waiters[id] = cont
            task?.send(.string(text)) { err in
                if let err { Task { await self.fail(id, err) } }
            }
        }
    }

    private func fail(_ id: Int, _ error: Error) {
        waiters.removeValue(forKey: id)?.resume(throwing: error)
    }
}
