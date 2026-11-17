import Foundation

/// What a capture stream films: a whole display or a single window.
public enum CaptureTarget: Equatable, Sendable {
    case display(id: UInt32), window(id: UInt32)
}

public enum CaptureTargets {
    /// Resolves the saved video source against what is on screen now. A saved display that
    /// is gone falls back to the main display; a window that is gone is unavailable (nil).
    public static func resolve(_ source: VideoSource, displayIDs: [UInt32], mainDisplayID: UInt32,
                               windowIDs: [UInt32]) -> CaptureTarget? {
        let main: CaptureTarget? = displayIDs.contains(mainDisplayID) ? .display(id: mainDisplayID) : nil
        switch source {
        case .mainDisplay:
            return main
        case .display(let id):
            return displayIDs.contains(id) ? .display(id: id) : main
        case .window(let id):
            return windowIDs.contains(id) ? .window(id: id) : nil
        }
    }
}

/// One ScreenCaptureKit stream to run.
public struct StreamPlan: Equatable, Sendable {
    public enum Video: Equatable, Sendable {
        /// Real video at the output size and frame rate, delivered to the sink.
        case full
        /// 2×2 px at 1 fps with no screen output: the stream exists only to carry audio.
        case placeholder
    }

    public let target: CaptureTarget
    public let video: Video
    public let systemAudio: Bool
    public let microphone: Bool

    public init(target: CaptureTarget, video: Video, systemAudio: Bool, microphone: Bool) {
        self.target = target
        self.video = video
        self.systemAudio = systemAudio
        self.microphone = microphone
    }
}

public enum CapturePlanner {
    /// The streams to start, in start order (the audio-carrying stream first).
    ///
    /// A window-filtered stream carries no audio from other apps (capture finding A = no), so
    /// with a window source audio travels on a separate placeholder stream on the main display.
    /// Audio only uses a placeholder stream on the main display (finding B = yes).
    public static func streams(mode: RecordingMode, target: CaptureTarget, mainDisplayID: UInt32,
                               systemAudio: Bool, microphone: Bool) -> [StreamPlan] {
        let audioCarrier = StreamPlan(target: .display(id: mainDisplayID), video: .placeholder,
                                      systemAudio: systemAudio, microphone: microphone)
        if mode == .audioOnly { return [audioCarrier] }
        switch target {
        case .display:
            return [StreamPlan(target: target, video: .full, systemAudio: systemAudio, microphone: microphone)]
        case .window:
            let window = StreamPlan(target: target, video: .full, systemAudio: false, microphone: false)
            return (systemAudio || microphone) ? [audioCarrier, window] : [window]
        }
    }
}

public enum WindowListing {
    /// Windows offered as a video source: on screen, titled, normal layer, at least
    /// 100×100 points, not Nastro's own.
    public static func isListable(title: String?, layer: Int, width: Double, height: Double,
                                  isOnScreen: Bool, isOwnApp: Bool) -> Bool {
        guard isOnScreen, !isOwnApp, layer == 0, width >= 100, height >= 100 else { return false }
        return !(title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
