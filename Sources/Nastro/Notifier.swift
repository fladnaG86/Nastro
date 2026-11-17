import AppKit
import Foundation
import NastroCore
import NastroMedia
import UserNotifications

/// User notifications. Clicking one that carries a file shows it in the Finder. Outside an
/// app bundle (`swift run`, the diagnostics) `UNUserNotificationCenter` raises an exception,
/// so messages go to standard error instead.
enum Notifier {
    private static let pathKey = "path"

    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    static func requestAuthorization() {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = ClickHandler.shared
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func recordingSaved(_ url: URL) {
        post(title: L10n.t(.recordingSaved), body: url.lastPathComponent, file: url)
    }

    /// A stop the user did not ask for (`.user` is just a save). `url` = the saved file, if any.
    static func recordingStopped(reason: StopReason, url: URL?) {
        guard let key = RecordingRules.stopMessageKey(reason) else {
            if let url { recordingSaved(url) }
            return
        }
        var body = L10n.t(key)
        if let url { body += "\n" + url.lastPathComponent }
        post(title: L10n.t(.recordingStopped), body: body, file: url)
    }

    static func recovered(_ outcomes: [RecoveryOutcome]) {
        var recovered: [URL] = []
        var damaged: [URL] = []
        for outcome in outcomes {
            switch outcome {
            case .recovered(let url): recovered.append(url)
            case .damaged(let url): damaged.append(url)
            }
        }
        if !recovered.isEmpty {
            post(title: L10n.t(.recordingRecovered),
                 body: recovered.map(\.lastPathComponent).joined(separator: "\n"), file: recovered.first)
        }
        if !damaged.isEmpty {
            post(title: L10n.t(.recordingDamaged),
                 body: damaged.map(\.lastPathComponent).joined(separator: "\n"), file: damaged.first)
        }
    }

    static func failed(_ message: String) {
        post(title: L10n.t(.appName), body: message, file: nil)
    }

    /// A failure that left a file the user should know about (e.g. a kept work file).
    static func failed(_ message: String, file: URL) {
        post(title: L10n.t(.appName), body: message + "\n" + file.path, file: file)
    }

    private static func post(title: String, body: String, file: URL?) {
        guard isAvailable else {
            FileHandle.standardError.write(Data("Nastro notification: \(title) — \(body)\n".utf8))
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let file { content.userInfo = [pathKey: file.path] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Shows banners while Nastro is frontmost and reveals the notification's file on click.
    private final class ClickHandler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
        static let shared = ClickHandler()

        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler:
                                        @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .sound])
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                    withCompletionHandler completionHandler: @escaping () -> Void) {
            if let path = response.notification.request.content.userInfo[Notifier.pathKey] as? String {
                let url = URL(fileURLWithPath: path)
                DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            completionHandler()
        }
    }
}
