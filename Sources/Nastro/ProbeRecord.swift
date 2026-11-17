import AppKit
import Foundation
import NastroCore
import NastroMedia

/// Diagnostics that drive the real `RecordingController` from the terminal.
///
/// `Nastro --probe-record <seconds> <display|window|audio>` records into `~/Movies/Nastro/`
/// with start() → wait → stop() → stop() again (the second call must be harmless) and ends
/// with `PROBE-RECORD ok <file>` (exit 0) or `PROBE-RECORD failed <reason>` (exit 1).
///
/// `Nastro --probe-recover` runs `recoverLeftovers()` on the default folder and prints one
/// `PROBE-RECOVER recovered|damaged <file>` line per outcome (`PROBE-RECOVER none` if none).
///
/// Settings go to a throwaway defaults domain so the app's own settings are never touched.
@MainActor
enum ProbeRecord {
    private static let defaultsSuite = "it.nastro.probe"

    nonisolated static func run(_ arguments: [String]) -> Never {
        guard arguments.count >= 2, let seconds = Double(arguments[0]), seconds > 0,
              ["display", "window", "audio"].contains(arguments[1]) else {
            print("usage: Nastro --probe-record <seconds> <display|window|audio>")
            exit(1)
        }
        // ScreenCaptureKit window filters need the window server connection NSApplication sets up.
        // `main()` runs on the main thread.
        MainActor.assumeIsolated { _ = NSApplication.shared }
        Task { @MainActor in exit(await record(seconds: seconds, source: arguments[1])) }
        dispatchMain()
    }

    nonisolated static func runRecover() -> Never {
        Task { @MainActor in
            let controller = makeController()
            await controller.recoverLeftovers()
            if controller.lastRecoveryOutcomes.isEmpty { print("PROBE-RECOVER none") }
            for outcome in controller.lastRecoveryOutcomes {
                switch outcome {
                case .recovered(let url): print("PROBE-RECOVER recovered \(url.path)")
                case .damaged(let url): print("PROBE-RECOVER damaged \(url.path)")
                }
            }
            cleanUp()
            exit(0)
        }
        dispatchMain()
    }

    private static func makeController() -> RecordingController {
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        return RecordingController(store: SettingsStore(defaults: UserDefaults(suiteName: defaultsSuite)!))
    }

    private static func cleanUp() { UserDefaults().removePersistentDomain(forName: defaultsSuite) }

    private static func record(seconds: Double, source: String) async -> Int32 {
        defer { cleanUp() }
        print("permissions: screen granted \(Permissions.screenGranted), "
            + "microphone status \(Permissions.microphoneStatus.rawValue) (3 = authorized)")
        let controller = makeController()
        var settings = Settings.default
        switch source {
        case "window":
            guard let window = try? await SourceCatalog.load().windows.first else {
                print("PROBE-RECORD failed no listable window on screen")
                return 1
            }
            settings.videoSource = .window(id: window.id)
            print("source: window \(window.id) \"\(window.title)\" (\(window.appName))")
        case "audio":
            settings.mode = .audioOnly
            print("source: audio only")
        default:
            print("source: main display")
        }
        controller.settings = settings

        await controller.start()
        guard case .recording = controller.state else {
            print("PROBE-RECORD failed start: \(controller.startProblem.map { "\($0)" } ?? "unknown")")
            return 1
        }
        print("controller: recording \(seconds) s")
        let end = Date().addingTimeInterval(seconds)
        var lastLevels = Date.distantPast
        while Date() < end, case .recording = controller.state {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Date().timeIntervalSince(lastLevels) >= 2 {
                lastLevels = Date()
                print(String(format: "levels: t=%ds system %.1f dB, microphone %.1f dB, warnings %@",
                             controller.elapsedSeconds, controller.systemLevelDB, controller.microphoneLevelDB,
                             "\(controller.warnings.map { "\($0)" }.sorted())"))
            }
        }
        await controller.stop()
        print("controller: first stop returned, state \(controller.state)")
        await controller.stop()
        print("controller: second stop returned, state \(controller.state)")
        print("warnings seen: \(controller.warningsSeen.map { "\($0)" }.sorted())")
        if let problem = controller.startProblem { print("start problem: \(problem)") }

        switch controller.lastOutcome {
        case .saved(let url)?:
            let exists = FileManager.default.fileExists(atPath: url.path)
            print("file exists after double stop: \(exists)")
            guard exists else {
                print("PROBE-RECORD failed file vanished: \(url.path)")
                return 1
            }
            print("PROBE-RECORD ok \(url.path)")
            return 0
        case let outcome:
            print("PROBE-RECORD failed \(outcome.map { "\($0)" } ?? "no outcome")")
            return 1
        }
    }
}
