import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published var connection: Connection = .qobuzClosed
}

/// Main process: menu bar item, settings, Qobuz relaunch, starting/stopping the player child.
@MainActor
final class Watcher: NSObject, NSApplicationDelegate {
    let model = AppModel()
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    var child: Process?
    var refreshing = false
    var appliedPort = Prefs.port
    var appliedSilent = Prefs.silent
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Now Bridge")
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("Relaunch Qobuz in Bridge Mode", #selector(relaunchQobuz)))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Now Bridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Prefs.qobuzID else { return }
            Task { @MainActor in await self?.ensureDebugPort() }
        }
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.prefsChanged() }
        }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }

        // When Now Bridge starts (so at login if "Open at login" is on)
        if Prefs.launchQobuzAtStart, NSRunningApplication.runningApplications(withBundleIdentifier: Prefs.qobuzID).isEmpty {
            relaunchQobuz()
        }
        statusItem.isVisible = Prefs.showIcon
        Task { await refresh() }
    }

    func applicationWillTerminate(_ n: Notification) { child?.terminate() }

    /// Opening Now Bridge again (Spotlight, Finder…) shows the settings: essential when the icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    // MARK: state

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }

        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Prefs.qobuzID).isEmpty
        let reachable = running ? await debugPortReachable() : false
        let c = Connection.derive(qobuzRunning: running, portReachable: reachable, state: StateFile.read())
        if model.connection != c { model.connection = c }
        updateStatusItem()
        syncChild(running: running)
    }

    func updateStatusItem() {
        statusItem.isVisible = Prefs.showIcon
        statusLine.title = model.connection.label
        var title = ""
        if Prefs.showTitle, case .connected(let text, _) = model.connection {
            title = " " + menuBarText(text)
        }
        statusItem.button?.title = title
    }

    func syncChild(running: Bool) {
        if running, child == nil, let exe = Bundle.main.executableURL {
            let p = Process()
            p.executableURL = exe
            p.arguments = ["--player"]
            p.terminationHandler = { [weak self] _ in Task { @MainActor in self?.child = nil } }
            if (try? p.run()) != nil { child = p }
        } else if !running, let c = child {
            c.terminate(); child = nil
        }
    }

    /// The port and silent audio are read when the player starts: restart it when they change.
    func prefsChanged() {
        updateStatusItem()
        if Prefs.port != appliedPort || Prefs.silent != appliedSilent {
            appliedPort = Prefs.port; appliedSilent = Prefs.silent
            child?.terminate()
        }
    }

    // MARK: launching Qobuz

    /// Qobuz was just opened normally (Dock, Spotlight…): if it doesn't expose the port, relaunch it once with it.
    func ensureDebugPort() async {
        guard Prefs.autoRelaunch else { return }
        try? await Task.sleep(for: .seconds(3))
        if await debugPortReachable() { return }
        relaunchQobuz()
    }

    @objc func relaunchQobuz() {
        let id = Prefs.qobuzID
        let port = Prefs.port
        Task {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) { app.terminate() }
            for _ in 0..<20 where !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.arguments = ["--remote-debugging-port=\(port)", "--remote-allow-origins=http://127.0.0.1:\(port)"]
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        }
    }

    // MARK: settings

    @objc func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(model: model, relaunch: { [weak self] in self?.relaunchQobuz() },
                                    diagnostics: { [weak self] in self?.diagnostics() ?? "" })
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Now Bridge"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: view)
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func diagnostics() -> String {
        let info = Bundle.main.infoDictionary
        let qobuz = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Prefs.qobuzID)
            .flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String } ?? "not found"
        return """
        Now Bridge \(info?["CFBundleShortVersionString"] as? String ?? "?")
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Qobuz \(qobuz)
        Debug port: \(Prefs.port)
        Status: \(model.connection.label)
        Silent audio: \(Prefs.silent)
        """
    }
}
