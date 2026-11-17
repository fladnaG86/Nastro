import Foundation

/// Something the user should know while a recording runs.
public enum Warning: Hashable, Sendable {
    case systemAudioSilent, microphoneSilent, microphoneLost
    /// The source is enabled but its audio is not going into the file (no track, or its
    /// track ended because the format changed).
    case systemAudioNotRecorded, microphoneNotRecorded

    public var messageKey: L10n.Key {
        switch self {
        case .systemAudioSilent: return .warningSystemAudioSilent
        case .microphoneSilent: return .warningMicrophoneSilent
        case .microphoneLost: return .warningMicrophoneLost
        case .systemAudioNotRecorded: return .warningSystemAudioNotRecorded
        case .microphoneNotRecorded: return .warningMicrophoneNotRecorded
        }
    }

    /// Lower is more serious.
    fileprivate var severity: Int {
        switch self {
        case .microphoneNotRecorded: return 0
        case .systemAudioNotRecorded: return 1
        case .microphoneLost: return 2
        case .microphoneSilent: return 3
        case .systemAudioSilent: return 4
        }
    }
}

/// Why a recording could not start.
public enum StartProblem: Equatable, Sendable {
    case screenPermission, microphonePermission, folder, sourceUnavailable, other

    public var messageKey: L10n.Key {
        switch self {
        case .screenPermission: return .problemScreenPermission
        case .microphonePermission: return .problemMicrophonePermission
        case .folder: return .problemFolder
        case .sourceUnavailable: return .problemSourceUnavailable
        case .other: return .problemOther
        }
    }
}

/// The step of a start that failed, as seen by the controller.
public enum StartFailure: Equatable, Sendable {
    case folder, sourceUnavailable, permissionDenied, noFirstFrame, other
}

/// Microphone authorization, independent of AVFoundation.
public enum MicrophoneAccess: Equatable, Sendable { case authorized, notDetermined, denied }

/// What `start()` does about the microphone permission before capturing.
public enum MicrophoneDecision: Equatable, Sendable { case proceed, ask, fail }

/// What is known about one enabled audio source at a timer tick.
public struct AudioSourceFacts: Equatable, Sendable {
    /// Its `SilenceDetector` reports silence.
    public var silent: Bool
    /// It delivered samples and then stopped delivering them.
    public var samplesStopped: Bool
    /// The writer has no track for it, or its track ended.
    public var notRecorded: Bool

    public init(silent: Bool, samplesStopped: Bool, notRecorded: Bool) {
        self.silent = silent
        self.samplesStopped = samplesStopped
        self.notRecorded = notRecorded
    }
}

/// The recording controller's decisions that need no screen or capture.
public enum RecordingRules {
    /// Seconds without samples after which a source counts as stopped.
    public static let samplesGrace: TimeInterval = 5
    /// Seconds a video recording may go without its first frame.
    public static let firstFrameLimit: TimeInterval = 5

    /// `nil` facts = the source is disabled. Per source only the most serious warning is kept:
    /// not recorded, then (microphone only) lost, then silent.
    public static func warnings(systemAudio: AudioSourceFacts?, microphone: AudioSourceFacts?) -> Set<Warning> {
        var result: Set<Warning> = []
        if let system = systemAudio {
            if system.notRecorded { result.insert(.systemAudioNotRecorded) }
            else if system.silent { result.insert(.systemAudioSilent) }
        }
        if let mic = microphone {
            if mic.notRecorded { result.insert(.microphoneNotRecorded) }
            else if mic.samplesStopped { result.insert(.microphoneLost) }
            else if mic.silent { result.insert(.microphoneSilent) }
        }
        return result
    }

    /// True when samples did arrive (`lastSampleAt` not nil) but none for `grace` seconds.
    public static func samplesStopped(lastSampleAt: TimeInterval?, now: TimeInterval,
                                      grace: TimeInterval = samplesGrace) -> Bool {
        guard let last = lastSampleAt else { return false }
        return now - last >= grace
    }

    /// Warnings in `current` not yet notified during this recording, most serious first.
    public static func warningsToNotify(current: Set<Warning>, alreadyNotified: Set<Warning>) -> [Warning] {
        current.subtracting(alreadyNotified).sorted { $0.severity < $1.severity }
    }

    public static func microphoneDecision(wanted: Bool, access: MicrophoneAccess) -> MicrophoneDecision {
        guard wanted else { return .proceed }
        switch access {
        case .authorized: return .proceed
        case .notDetermined: return .ask
        case .denied: return .fail
        }
    }

    /// Checked before anything else: the screen permission is needed in every mode (audio
    /// travels on a screen stream), the microphone one only when the microphone is enabled.
    public static func permissionProblem(screenGranted: Bool, microphoneWanted: Bool,
                                         microphoneAuthorized: Bool) -> StartProblem? {
        if !screenGranted { return .screenPermission }
        if microphoneWanted, !microphoneAuthorized { return .microphonePermission }
        return nil
    }

    public static func startProblem(for failure: StartFailure, screenGranted: Bool, microphoneWanted: Bool,
                                    microphoneAuthorized: Bool) -> StartProblem {
        switch failure {
        case .folder: return .folder
        case .sourceUnavailable: return .sourceUnavailable
        case .noFirstFrame, .other: return .other
        case .permissionDenied:
            // With both permissions granted the user declined the capture prompt: screen.
            return permissionProblem(screenGranted: screenGranted, microphoneWanted: microphoneWanted,
                                     microphoneAuthorized: microphoneAuthorized) ?? .screenPermission
        }
    }

    public static func firstFrameOverdue(expectsVideo: Bool, sawVideo: Bool, secondsSinceStart: TimeInterval,
                                         limit: TimeInterval = firstFrameLimit) -> Bool {
        expectsVideo && !sawVideo && secondsSinceStart >= limit
    }

    /// Why a stream that stopped by itself ended the recording, from its `SCStreamError` code
    /// (`nil` = not a ScreenCaptureKit stream error).
    public static func stopReason(streamErrorCode code: Int?) -> StopReason {
        switch code {
        case -3813, -3814, -3815: return .sourceLost   // no window list / no display list / no capture source
        case -3817: return .user                        // stopped from the system's sharing controls
        case -3822: return .diskFull                    // insufficient storage
        default: return .streamError
        }
    }

    /// The explanation that goes with a stop the user did not ask for.
    public static func stopMessageKey(_ reason: StopReason) -> L10n.Key? {
        switch reason {
        case .user: return nil
        case .sourceLost: return .stoppedSourceLost
        case .streamError: return .stoppedStreamError
        case .diskFull: return .stoppedDiskFull
        }
    }

    /// Finalizing writes a copy about as large as the work file before the work file is
    /// deleted. Unknown free space: try anyway (a failed finalization keeps the work file).
    public static func hasRoomToFinalize(freeBytes: Int64?, workFileBytes: Int64) -> Bool {
        guard let free = freeBytes else { return true }
        return free >= workFileBytes
    }
}
