import SwiftUI
import NastroCore
import NastroMedia

/// Entry point: `Nastro --probe-record <seconds> <display|window|audio>` and
/// `Nastro --probe-recover` run diagnostics instead of the menu bar app.
@main
enum NastroMain {
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--probe-record") {
            ProbeRecord.run(Array(arguments[(index + 1)...]))
        } else if arguments.contains("--probe-recover") {
            ProbeRecord.runRecover()
        } else {
            NastroApp.main()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = RecordingController(store: SettingsStore(defaults: .standard))

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.requestAuthorization()
        Task { await controller.recoverLeftovers() }
    }
}

struct NastroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(L10n.t(.appName), systemImage: "record.circle") {
            MenuContent(controller: appDelegate.controller)
        }
    }
}

/// Minimal menu; the full one comes later.
private struct MenuContent: View {
    @ObservedObject var controller: RecordingController

    var body: some View {
        Button(isRecording ? L10n.t(.stopRecording) : L10n.t(.startRecording)) { controller.toggle() }
            .disabled(!canToggle)
        Divider()
        Button(L10n.t(.quit)) { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var isRecording: Bool {
        if case .recording = controller.state { return true }
        return false
    }

    private var canToggle: Bool {
        switch controller.state {
        case .idle, .recording: return true
        default: return false
        }
    }
}
