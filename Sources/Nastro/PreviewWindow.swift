import AppKit
import NastroCore
import SwiftUI

/// Diagnostic: `Nastro --preview <idle|recording|problem|settings>` shows one view in an
/// ordinary titled window, with fixed values. No menu bar item, no capture, no permission
/// request; it stays open until the process is killed.
@MainActor
enum PreviewWindow {
    private static var window: NSWindow?

    nonisolated static func run(_ arguments: [String]) -> Never {
        let modes = ["idle", "recording", "problem", "settings"]
        guard let mode = arguments.first, modes.contains(mode) else {
            print("usage: Nastro --preview <\(modes.joined(separator: "|"))>")
            exit(1)
        }
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            let root: AnyView
            switch mode {
            case "recording": root = AnyView(PreviewPanel(status: recordingStatus, loadSources: false))
            case "problem": root = AnyView(PreviewPanel(status: idleStatus(problem: .screenPermission), loadSources: true))
            case "settings": root = AnyView(PreviewSettings())
            default: root = AnyView(PreviewPanel(status: idleStatus(problem: nil), loadSources: true))
            }
            let host = NSHostingController(rootView: root)
            host.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable]
            window.title = "Nastro preview — \(mode)"
            window.center()
            window.makeKeyAndOrderFront(nil)
            self.window = window
            app.activate()
            app.run()
        }
        exit(0)
    }

    private static func idleStatus(problem: StartProblem?) -> PanelStatus {
        PanelStatus(state: .idle, elapsedSeconds: 0, systemLevelDB: AudioLevel.floorDB,
                    microphoneLevelDB: AudioLevel.floorDB, warnings: [], problem: problem)
    }

    private static let recordingStatus = PanelStatus(
        state: .recording(since: Date()), elapsedSeconds: 12 * 60 + 34, systemLevelDB: -12,
        microphoneLevelDB: -30, warnings: [.microphoneSilent, .systemAudioNotRecorded], problem: nil)
}

private struct PreviewPanel: View {
    let status: PanelStatus
    let loadSources: Bool
    @State private var settings = NastroCore.Settings.default
    @State private var sources = PanelSources(
        displays: [DisplayInfo(id: 1, name: L10n.t(.mainDisplayPlaceholder), isMain: true)],
        microphones: [MicInfo(id: "preview", name: "MacBook Pro Microphone")],
        defaultMicrophoneName: "MacBook Pro Microphone")

    var body: some View {
        MenuView(status: status, sources: sources, settings: $settings, actions: PanelActions())
            .task {
                guard loadSources else { return }
                let loaded = await PanelSources.load()
                if !loaded.displays.isEmpty { sources.displays = loaded.displays; sources.windows = loaded.windows }
                if !loaded.microphones.isEmpty {
                    sources.microphones = loaded.microphones
                    sources.defaultMicrophoneName = loaded.defaultMicrophoneName
                }
            }
    }
}

private struct PreviewSettings: View {
    @State private var settings = NastroCore.Settings.default

    var body: some View {
        SettingsView(settings: $settings, microphones: SourceCatalog.microphones())
    }
}
