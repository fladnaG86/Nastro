import AppKit
import Foundation
import NastroCore
import NastroMedia
import UserNotifications

/// User notifications. Clicking one that carries a file shows it in the Finder (or opens it,
/// for a summary). Outside an
/// app bundle (`swift run`, the diagnostics) `UNUserNotificationCenter` raises an exception,
/// so messages go to standard error instead.
enum Notifier {
    private static let pathKey = "path"
    /// true = clicking opens the file instead of revealing it.
    private static let openKey = "open"

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
            case .noRoom(let url):
                post(title: L10n.t(.appName),
                     body: String(format: L10n.t(.recoveryNoRoom), url.lastPathComponent), file: url)
            case .failed(let url):
                failed(L10n.t(.finalizeFailed) + " " + L10n.t(.workFileKept), file: url)
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

    /// Clicking opens the summary.
    static func summaryReady(_ summary: URL) {
        post(title: L10n.t(.summaryReady), body: summary.lastPathComponent, file: summary, opensFile: true)
    }

    /// Clicking reveals the transcript, if one was saved.
    static func summaryFailed(_ message: String, transcript: URL?) {
        post(title: L10n.t(.appName), body: message, file: transcript)
    }

    private static func post(title: String, body: String, file: URL?, opensFile: Bool = false) {
        guard isAvailable else {
            FileHandle.standardError.write(Data("Nastro notification: \(title) — \(body)\n".utf8))
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let file { content.userInfo = [pathKey: file.path, openKey: opensFile] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Shows banners while Nastro is frontmost and reveals (or opens) the notification's file on click.
    private final class ClickHandler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
        static let shared = ClickHandler()

        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler:
                                        @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .sound])
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                    withCompletionHandler completionHandler: @escaping () -> Void) {
            let userInfo = response.notification.request.content.userInfo
            if let path = userInfo[Notifier.pathKey] as? String {
                let url = URL(fileURLWithPath: path)
                let opens = userInfo[Notifier.openKey] as? Bool ?? false
                DispatchQueue.main.async {
                    if opens {
                        NSWorkspace.shared.open(url)
                    } else {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
            completionHandler()
        }
    }
}
