import Combine
import SwiftUI
import NastroCore
import NastroMedia

/// Entry point: `Nastro --probe-record <seconds> <display|window|audio>`,
/// `Nastro --probe-recover` and `Nastro --preview <idle|recording|problem|settings>` run
/// diagnostics instead of the menu bar app.
@main
enum NastroMain {
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--probe-record") {
            ProbeRecord.run(Array(arguments[(index + 1)...]))
        } else if arguments.contains("--probe-recover") {
            ProbeRecord.runRecover()
        } else if let index = arguments.firstIndex(of: "--preview") {
            PreviewWindow.run(Array(arguments[(index + 1)...]))
        } else {
            NastroApp.main()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = RecordingController(store: SettingsStore(defaults: .standard))
    private var hotKeyLetter: AnyCancellable?
    private static let askedScreenKey = "askedScreenPermission"

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.requestAuthorization()
        let defaults = UserDefaults.standard
        if !Permissions.screenGranted, !defaults.bool(forKey: Self.askedScreenKey) {
            defaults.set(true, forKey: Self.askedScreenKey)
            Permissions.requestScreen()
        }
        hotKeyLetter = controller.$settings
            .map(\.hotKeyLetter)
            .removeDuplicates()
            .sink { [weak self] letter in self?.registerHotKey(letter) }
        Task { await controller.recoverLeftovers() }
    }

    /// ⌃⌥ + the letter; `HotKeyLetters.keyCode` refuses the letters reserved by Postino.
    private func registerHotKey(_ letter: String) {
        HotKeys.unregisterAll()
        guard let keyCode = HotKeyLetters.keyCode(for: letter) else { return }
        HotKeys.register(id: 1, keyCode: keyCode, modifiers: HotKeyLetters.modifiers) { [weak self] in
            self?.controller.toggle()
        }
    }
}

struct NastroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            LiveMenuPanel(controller: appDelegate.controller)
        } label: {
            LiveMenuBarLabel(controller: appDelegate.controller)
        }
        .menuBarExtraStyle(.window)

        Settings {
            LiveSettings(controller: appDelegate.controller)
        }
    }
}

private struct LiveMenuBarLabel: View {
    @ObservedObject var controller: RecordingController

    var body: some View {
        let problem = MenuLayout.displayedProblem(startProblem: controller.startProblem,
                                                  screenGranted: Permissions.screenGranted)
        MenuBarLabelView(label: MenuBarLabel.make(
            state: controller.state, elapsedSeconds: controller.elapsedSeconds,
            attention: MenuBarLabel.needsAttention(warnings: controller.warnings, problem: problem)))
    }
}

/// Feeds `MenuView` from the controller; reloads the source lists each time the panel opens.
private struct LiveMenuPanel: View {
    @ObservedObject var controller: RecordingController
    @State private var sources = PanelSources()
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MenuView(status: status, sources: sources, settings: $controller.settings, actions: actions)
            .task { await reload() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
                Task { await reload() }
            }
    }

    private var status: PanelStatus {
        PanelStatus(state: controller.state, elapsedSeconds: controller.elapsedSeconds,
                    systemLevelDB: controller.systemLevelDB, microphoneLevelDB: controller.microphoneLevelDB,
                    warnings: controller.warnings,
                    problem: MenuLayout.displayedProblem(startProblem: controller.startProblem,
                                                         screenGranted: Permissions.screenGranted))
    }

    private var actions: PanelActions {
        PanelActions(
            toggle: { controller.toggle() },
            openFolder: {
                let folder = controller.settings.validated().outputFolder
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                NSWorkspace.shared.open(folder)
                dismiss()
            },
            openSettings: {
                dismiss()
                NSApp.activate()
                openSettings()
            },
            quit: { NSApplication.shared.terminate(nil) },
            openSystemSettings: { pane in
                Permissions.openSystemSettings(pane == .screen ? .screen : .microphone)
                dismiss()
            })
    }

    private func reload() async {
        // Only while idle: the lists are not shown otherwise.
        guard controller.state == .idle else { return }
        sources = await PanelSources.load()
    }
}

private struct LiveSettings: View {
    @ObservedObject var controller: RecordingController
    @State private var microphones: [MicInfo] = []

    var body: some View {
        SettingsView(settings: $controller.settings, microphones: microphones)
            .onAppear {
                microphones = SourceCatalog.microphones()
                NSApp.activate()
            }
    }
}
