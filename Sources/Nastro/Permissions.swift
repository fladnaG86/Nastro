import AppKit
import AVFoundation
import CoreGraphics

/// Screen Recording and Microphone permission checks.
enum Permissions {
    enum Pane { case screen, microphone }

    static var screenGranted: Bool { CGPreflightScreenCaptureAccess() }

    static func requestScreen() { _ = CGRequestScreenCaptureAccess() }

    static var microphoneStatus: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }

    static func requestMicrophone() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }

    static func openSystemSettings(_ pane: Pane) {
        let anchor = pane == .screen ? "Privacy_ScreenCapture" : "Privacy_Microphone"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
