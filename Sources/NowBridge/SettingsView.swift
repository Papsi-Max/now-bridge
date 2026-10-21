import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var relaunch: () -> Void
    var diagnostics: () -> String
    @State private var tab = Tab.general

    enum Tab: String, CaseIterable, Identifiable {
        case general = "General", qobuz = "Qobuz", about = "About"
        var id: Self { self }
        var icon: String {
            switch self {
            case .general: "gearshape"
            case .qobuz: "dot.radiowaves.left.and.right"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Tab.allCases) { t in
                    Button { tab = t } label: {
                        VStack(spacing: 3) {
                            Image(systemName: t.icon).font(.system(size: 18))
                            Text(t.rawValue).font(.system(size: 11))
                        }
                        .frame(width: 76, height: 48)
                        .background(tab == t ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(tab == t ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 10)

            switch tab {
            case .general: GeneralTab()
            case .qobuz: QobuzTab(model: model, relaunch: relaunch)
            case .about: AboutTab(diagnostics: diagnostics)
            }
        }
        .frame(width: 480, height: 560)
    }
}

struct GeneralTab: View {
    @AppStorage("showIcon") private var showIcon = true
    @AppStorage("showTitle") private var showTitle = false
    @AppStorage("launchQobuzAtStart") private var launchQobuz = false
    @AppStorage("autoRelaunch") private var autoRelaunch = true
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: setLogin))
                Toggle("Show icon in menu bar", isOn: $showIcon)
                Toggle("Show current track in menu bar", isOn: $showTitle)
            } footer: {
                Text(loginError ?? "Hide the icon and Now Bridge keeps running in the background. Open Now Bridge again at any time to show these settings.")
            }
            Section {
                Toggle("Open Qobuz when Now Bridge starts", isOn: $launchQobuz)
                Toggle("Relaunch Qobuz in bridge mode when opened normally", isOn: $autoRelaunch)
            } header: {
                Text("Qobuz")
            } footer: {
                Text("Now Bridge reads Qobuz through a local debug port, so Qobuz must be started in bridge mode. With these options, that happens automatically. Qobuz briefly closes and reopens when it was started without it.")
            }
        }
        .formStyle(.grouped)
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not change the login item: \(error.localizedDescription). You can add Now Bridge in System Settings → General → Login Items instead."
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct QobuzTab: View {
    @ObservedObject var model: AppModel
    var relaunch: () -> Void
    @AppStorage("port") private var port = Prefs.defaultPort
    @AppStorage("silent") private var silent = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: 8, height: 8)
                        Text(model.connection.label).multilineTextAlignment(.trailing)
                    }
                }
                LabeledContent("Debug port") {
                    TextField("", value: $port, format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                }
                Button("Relaunch Qobuz in Bridge Mode", action: relaunch)
            } footer: {
                Text("Default port: \(Prefs.defaultPort). Relaunch Qobuz after changing the port. The port only listens on this Mac (127.0.0.1).")
            }
            Section {
                Toggle("Silent audio helper", isOn: $silent)
            } header: {
                Text("Compatibility")
            } footer: {
                Text("Plays an inaudible sound so macOS treats Now Bridge as an active audio app. Only turn this on if Qobuz does not show up in Now Playing.")
            }
        }
        .formStyle(.grouped)
    }

    private var color: Color {
        switch model.connection.isHealthy {
        case true?: .green
        case false?: .orange
        case nil: .gray
        }
    }
}

struct AboutTab: View {
    var diagnostics: () -> String
    @State private var copied = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 84, height: 84)
                    Text("Now Bridge").font(.title2.bold())
                    Text("Version \(version)").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section {
                Button(copied ? "Copied" : "Copy diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diagnostics(), forType: .string)
                    copied = true
                }
            } footer: {
                Text("Useful when reporting a problem.")
            }
            Section {
                Text("Now Bridge shows Qobuz in macOS Now Playing and routes the media keys back to it. It is an independent project and is not affiliated with Qobuz, Apple or Spotify. It does not use any private Qobuz API or account token.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
