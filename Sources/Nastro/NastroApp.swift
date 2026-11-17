import SwiftUI
import NastroCore
import NastroMedia

@main
struct NastroApp: App {
    var body: some Scene {
        MenuBarExtra(L10n.t(.appName), systemImage: "record.circle") {
            Button(L10n.t(.quit)) { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
