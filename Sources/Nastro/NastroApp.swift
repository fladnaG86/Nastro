import SwiftUI
import NastroCore
import NastroMedia

/// Entry point: `Nastro --probe-record <seconds> <display|window|audio>` runs the capture
/// diagnostic instead of the menu bar app.
@main
enum NastroMain {
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--probe-record") {
            ProbeRecord.run(Array(arguments[(index + 1)...]))
        } else {
            NastroApp.main()
        }
    }
}

struct NastroApp: App {
    var body: some Scene {
        MenuBarExtra(L10n.t(.appName), systemImage: "record.circle") {
            Button(L10n.t(.quit)) { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
