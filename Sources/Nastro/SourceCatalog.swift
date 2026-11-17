import AppKit
import AVFoundation
import CoreGraphics
import NastroCore
import ScreenCaptureKit

struct DisplayInfo: Identifiable, Equatable { let id: UInt32; let name: String; let isMain: Bool }
struct WindowInfo: Identifiable, Equatable { let id: UInt32; let title: String; let appName: String }
struct MicInfo: Identifiable, Equatable { let id: String; let name: String }

struct Sources {
    let displays: [DisplayInfo]
    let windows: [WindowInfo]
    let content: SCShareableContent
}

/// What can be recorded right now: displays, windows and microphones.
enum SourceCatalog {
    static let appBundleID = "it.nastro.app"

    /// Nastro itself, bundled (`it.nastro.app`) or run as a bare binary (this process).
    static func isNastro(_ app: SCRunningApplication?) -> Bool {
        guard let app else { return false }
        return app.bundleIdentifier == appBundleID || app.processID == getpid()
    }

    static func load() async throws -> Sources {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let names = await MainActor.run { screenNames() }
        let mainID = CGMainDisplayID()
        let displays = content.displays.map { display in
            DisplayInfo(id: display.displayID,
                        name: names[display.displayID] ?? "Display \(display.displayID)",
                        isMain: display.displayID == mainID)
        }
        let windows = content.windows
            .filter {
                WindowListing.isListable(title: $0.title, layer: $0.windowLayer,
                                         width: $0.frame.width, height: $0.frame.height,
                                         isOnScreen: $0.isOnScreen, isOwnApp: isNastro($0.owningApplication))
            }
            .map {
                WindowInfo(id: $0.windowID, title: $0.title ?? "",
                           appName: $0.owningApplication?.applicationName ?? "")
            }
        return Sources(displays: displays, windows: windows, content: content)
    }

    static func microphones() -> [MicInfo] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio,
                                         position: .unspecified)
            .devices
            .map { MicInfo(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// `NSScreen.localizedName` by CoreGraphics display ID.
    @MainActor
    private static func screenNames() -> [UInt32: String] {
        var names: [UInt32: String] = [:]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[number.uint32Value] = screen.localizedName
            }
        }
        return names
    }
}
