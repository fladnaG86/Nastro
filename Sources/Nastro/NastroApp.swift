import Combine
import SwiftUI
import NastroCore
import NastroMedia

/// Entry point: `Nastro --probe-record <seconds> <display|window|audio>`,
/// `Nastro --probe-recover`, `Nastro --probe-transcribe <file>`, `Nastro --probe-summarize <file>` and
/// `Nastro --preview <idle|recording|problem|settings|settings-recording|menubar>` run
/// diagnostics instead of the menu bar app.
@main
enum NastroMain {
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--probe-record") {
            ProbeRecord.run(Array(arguments[(index + 1)...]))
        } else if arguments.contains("--probe-recover") {
            ProbeRecord.runRecover()
        } else if let index = arguments.firstIndex(of: "--probe-transcribe") {
            ProbeTranscribe.run(Array(arguments[(index + 1)...]))
        } else if let index = arguments.firstIndex(of: "--probe-summarize") {
            ProbeSummarize.run(Array(arguments[(index + 1)...]))
        } else if let index = arguments.firstIndex(of: "--preview") {
            PreviewWindow.run(Array(arguments[(index + 1)...]))
        } else {
            NastroApp.main()
        }
    }
}

/// App facts the views show besides the controller's: the hotkey registration and the screen
/// permission, re-read each time the panel opens.
@MainActor
final class AppStatus: ObservableObject {
    @Published var hotKey: HotKeyOutcome = .notRegistered
    @Published var screenGranted = Permissions.screenGranted
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = RecordingController(store: SettingsStore(defaults: .standard))
    let status = AppStatus()
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
        var registered = false
        if let keyCode = HotKeyLetters.keyCode(for: letter) {
            registered = HotKeys.register(id: 1, keyCode: keyCode, modifiers: HotKeyLetters.modifiers) { [weak self] in
                self?.controller.toggle()
            }
        }
        status.hotKey = HotKeyLetters.outcome(letter: letter, registered: registered)
    }
}

struct NastroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            LiveMenuPanel(controller: appDelegate.controller, app: appDelegate.status)
        } label: {
            LiveMenuBarLabel(controller: appDelegate.controller, app: appDelegate.status)
        }
        .menuBarExtraStyle(.window)

        Settings {
            LiveSettings(controller: appDelegate.controller, app: appDelegate.status)
        }
    }
}

private struct LiveMenuBarLabel: View {
    @ObservedObject var controller: RecordingController
    @ObservedObject var app: AppStatus

    var body: some View {
        let problem = MenuLayout.displayedProblem(startProblem: controller.startProblem,
                                                  screenGranted: app.screenGranted)
        MenuBarLabelView(label: MenuBarLabel.make(
            state: controller.state, elapsedSeconds: controller.elapsedSeconds,
            attention: MenuBarLabel.needsAttention(warnings: controller.warnings, problem: problem),
            critical: MenuBarLabel.isCritical(warnings: controller.warnings)))
    }
}

/// Feeds `MenuView` from the controller; re-reads the screen permission and reloads the source
/// lists each time the panel opens.
private struct LiveMenuPanel: View {
    @ObservedObject var controller: RecordingController
    @ObservedObject var app: AppStatus
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
                                                         screenGranted: app.screenGranted),
                    hotKey: app.hotKey, recordingSettings: controller.recordingSettings)
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
        app.screenGranted = Permissions.screenGranted
        // Only while idle: the lists are not shown otherwise.
        guard controller.state == .idle else { return }
        let loaded = await PanelSources.load()
        sources = loaded
        // A saved window that has closed: record the main display instead, as the picker shows.
        // `controller.state` is read again after the await, so a running recording is never touched.
        if let replacement = SourceChoice.sourceToSave(
            saved: controller.settings.videoSource,
            windowIDs: loaded.screenListsLoaded ? loaded.windows.map(\.id) : nil,
            state: controller.state) {
            controller.settings.videoSource = replacement
        }
    }
}

private struct LiveSettings: View {
    @ObservedObject var controller: RecordingController
    @ObservedObject var app: AppStatus
    @State private var microphones: [MicInfo] = []

    var body: some View {
        SettingsView(settings: $controller.settings, microphones: microphones,
                     locked: SettingsLock.isLocked(controller.state), hotKey: app.hotKey)
            .onAppear {
                microphones = SourceCatalog.microphones()
                NSApp.activate()
            }
    }
}
