import AppKit

Prefs.register()

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate: NSApplicationDelegate = CommandLine.arguments.contains("--player") ? Player() : Watcher()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
