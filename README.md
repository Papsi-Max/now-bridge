# Now Bridge

<p align="center"><img src="Resources/icon-preview.png" width="128" alt="Now Bridge icon"></p>

Now Bridge makes **Qobuz** show up in macOS **Now Playing** (menu bar widget, Control Center) and makes
the keyboard media keys control it. It is a small menu bar app written in Swift, with no dependencies.

> **Independent project.** Not affiliated with, endorsed by, or sponsored by Qobuz, Apple or Spotify.
> "Qobuz" is a trademark of its owners. Now Bridge uses no private Qobuz API and no account token: it only
> reads the interface of the desktop app you already run, through Electron's local debugging port
> (`127.0.0.1` only).

## Why

The Qobuz desktop app is an Electron app with a separate native audio engine. It never tells macOS what is
playing (no Media Session), so macOS shows nothing and the media keys do nothing.

## How it works

1. Qobuz is launched with `--remote-debugging-port=9222` (Now Bridge does this for you).
2. Now Bridge reads the title, artist, album, cover, position and play/pause state from Qobuz's player
   interface over the Chrome DevTools Protocol.
3. It publishes them through `MPNowPlayingInfoCenter` and receives play/pause/next/previous through
   `MPRemoteCommandCenter`, which it forwards to Qobuz by clicking the matching buttons.

Two processes run from the same executable: the main one (menu bar icon, settings, relaunching Qobuz) and a
short-lived `--player` child that talks to Now Playing. The child only exists while Qobuz is open, because
macOS keeps an app listed as a player for as long as its process is alive.

## Requirements

- macOS 14 or later
- Qobuz desktop app (tested with 8.3.0 on macOS 27)
- Swift 5.9+ toolchain (Xcode or Command Line Tools) to build from source

## Install

There is no notarized download yet: you build it yourself.

```bash
git clone https://github.com/Papsi-Max/now-bridge.git
cd now-bridge
./build.sh          # produces build/NowBridge.app, ad hoc signed
open build/NowBridge.app
```

The app is not notarized, so on first launch right-click it → **Open**. For "Open at login" to work reliably,
move it to `/Applications` first.

## Settings

Open them from the menu bar icon (**Settings…**, ⌘,) or by opening Now Bridge again.

- **General**: open at login, show/hide the menu bar icon, show the current track in the menu bar, open
  Qobuz when Now Bridge starts, relaunch Qobuz in bridge mode when it was opened normally.
- **Qobuz**: connection status, debug port, manual relaunch, and a silent-audio helper to use only if macOS
  does not list the app.
- **About**: version and a "Copy diagnostics" button for bug reports.

## Development

```bash
swift test          # unit tests
./build.sh          # build the app bundle
swift Tools/make-icon.swift   # regenerate Resources/AppIcon.icns
```

Code layout (`Sources/NowBridge`):

| File | Role |
| --- | --- |
| `Logic.swift` | Pure, tested logic: parsing the page reading, connection status |
| `Player.swift` | Child process: polls Qobuz, publishes to Now Playing, forwards media keys |
| `Watcher.swift` | Main process: menu bar, settings window, launching Qobuz, supervising the child |
| `CDP.swift` | Minimal DevTools Protocol client |
| `SettingsView.swift` | SwiftUI settings |
| `Shared.swift` | Preferences and the state file shared between both processes |

## Limitations

- The Qobuz interface is read through CSS selectors (`.player__…`, in `readJS`). A Qobuz update can change
  them; the settings then show "Player not found". Selectors are in one place, so fixes are small.
- Seeking from the system widget is not supported.
- Qobuz must run in bridge mode. If you open it normally, Now Bridge relaunches it once (it briefly closes
  and reopens). You can turn this off in Settings.
- Modifying the Qobuz app itself is deliberately avoided.

## License

See [LICENSE](LICENSE).
