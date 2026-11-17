import Foundation

/// What the menu bar item shows.
public struct MenuBarLabel: Equatable, Sendable {
    public static let warningSymbol = "exclamationmark.triangle.fill"

    public var symbol: String
    public var isRed: Bool
    /// Running time, only while recording.
    public var elapsed: String?
    /// Adds `warningSymbol` next to the main symbol.
    public var showsWarning: Bool

    public init(symbol: String, isRed: Bool, elapsed: String?, showsWarning: Bool) {
        self.symbol = symbol
        self.isRed = isRed
        self.elapsed = elapsed
        self.showsWarning = showsWarning
    }

    public static func make(state: RecorderState, elapsedSeconds: Int, attention: Bool) -> MenuBarLabel {
        switch state {
        case .idle, .starting:
            return MenuBarLabel(symbol: "record.circle", isRed: false, elapsed: nil, showsWarning: attention)
        case .recording:
            return MenuBarLabel(symbol: "record.circle.fill", isRed: true,
                                elapsed: TimeFormat.elapsed(elapsedSeconds), showsWarning: attention)
        case .finalizing:
            return MenuBarLabel(symbol: "hourglass", isRed: false, elapsed: nil, showsWarning: attention)
        }
    }

    /// A live warning, or a problem the menu explains (for example a missing permission).
    public static func needsAttention(warnings: Set<Warning>, problem: StartProblem?) -> Bool {
        !warnings.isEmpty || problem != nil
    }
}

/// A block of rows in the menu panel.
public enum MenuSection: Equatable, Sendable {
    case problem, start, mode, videoSource, audio
    case stop, meters, preparing
    case openFolder, settings, quit
}

/// A System Settings privacy pane.
public enum PermissionPane: Equatable, Sendable { case screen, microphone }

public enum MenuLayout {
    /// The rows to show, in order. While recording or preparing the file there are no source
    /// choices and no Quit (quitting would cut the file short).
    public static func sections(state: RecorderState, mode: RecordingMode, problem: StartProblem?) -> [MenuSection] {
        switch state {
        case .idle, .starting:
            var rows: [MenuSection] = problem == nil ? [] : [.problem]
            rows += [.start, .mode]
            if mode == .videoAndAudio { rows.append(.videoSource) }
            rows += [.audio, .openFolder, .settings, .quit]
            return rows
        case .recording:
            return [.stop, .meters, .openFolder, .settings]
        case .finalizing:
            return [.preparing, .openFolder, .settings]
        }
    }

    public static func choicesEditable(_ state: RecorderState) -> Bool { state == .idle }

    public static func startEnabled(_ state: RecorderState) -> Bool { state == .idle }

    /// The last start problem, or a missing screen permission before any attempt.
    public static func displayedProblem(startProblem: StartProblem?, screenGranted: Bool) -> StartProblem? {
        startProblem ?? (screenGranted ? nil : .screenPermission)
    }

    /// The pane that fixes a permission problem; nil for other problems.
    public static func permissionPane(for problem: StartProblem) -> PermissionPane? {
        switch problem {
        case .screenPermission: return .screen
        case .microphonePermission: return .microphone
        case .folder, .sourceUnavailable, .other: return nil
        }
    }
}

/// Level meters on a -60…0 dB scale.
public enum LevelMeter {
    public static let floorDB: Float = -60

    /// 0 at or below -60 dB, 1 at or above 0 dB, linear in dB between.
    public static func fraction(_ db: Float) -> Double {
        guard !db.isNaN else { return 0 }
        return Double(min(max((db - floorDB) / -floorDB, 0), 1))
    }
}

/// The audio source a meter shows.
public enum AudioChannel: Sendable { case system, microphone }

public enum MeterWarnings {
    /// Warnings shown under one meter, most serious first.
    public static func `for`(_ channel: AudioChannel, in warnings: Set<Warning>) -> [Warning] {
        let order: [Warning]
        switch channel {
        case .system: order = [.systemAudioNotRecorded, .systemAudioSilent]
        case .microphone: order = [.microphoneNotRecorded, .microphoneLost, .microphoneSilent]
        }
        return order.filter(warnings.contains)
    }

    /// A voice is missing from the file: must be impossible to miss.
    public static func isCritical(_ warning: Warning) -> Bool {
        warning == .systemAudioNotRecorded || warning == .microphoneNotRecorded
    }
}

/// The global hotkey: always Control+Option + a letter.
public enum HotKeyLetters {
    /// Carbon `controlKey | optionKey`.
    public static let modifiers = 0x1000 | 0x0800

    /// A–Z without the letters reserved by another app.
    public static let allowed: [String] = (UnicodeScalar("A").value...UnicodeScalar("Z").value)
        .compactMap { UnicodeScalar($0).map { String(Character($0)) } }
        .filter { !Settings.reservedLetters.contains($0) }

    /// Carbon virtual key codes (`kVK_ANSI_*`, US layout positions).
    private static let codes: [String: Int] = [
        "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05, "Z": 0x06, "X": 0x07,
        "C": 0x08, "V": 0x09, "B": 0x0B, "Q": 0x0C, "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10,
        "T": 0x11, "O": 0x1F, "U": 0x20, "I": 0x22, "P": 0x23, "L": 0x25, "J": 0x26, "K": 0x28,
        "N": 0x2D, "M": 0x2E,
    ]

    /// nil for anything that is not an allowed letter, so a reserved one can never be registered.
    public static func keyCode(for letter: String) -> Int? {
        let upper = letter.uppercased()
        guard allowed.contains(upper) else { return nil }
        return codes[upper]
    }

    public static func display(_ letter: String) -> String { "⌃⌥" + letter.uppercased() }
}

public enum SourceChoice {
    /// "App — Title", or whichever of the two is not empty.
    public static func windowLabel(app: String, title: String) -> String {
        let a = app.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return t }
        if t.isEmpty { return a }
        return "\(a) — \(t)"
    }

    /// Choosing the main display follows whichever display is main at recording time.
    public static func source(forDisplay id: UInt32, isMain: Bool) -> VideoSource {
        isMain ? .mainDisplay : .display(id: id)
    }

    public static func isAvailable(_ source: VideoSource, displayIDs: [UInt32], windowIDs: [UInt32]) -> Bool {
        switch source {
        case .mainDisplay: return true
        case .display(let id): return displayIDs.contains(id)
        case .window(let id): return windowIDs.contains(id)
        }
    }

    /// The name of the microphone that will be used; nil when the chosen one is not connected
    /// (or the system default is unknown).
    public static func microphoneName(selectedID: String?, available: [(id: String, name: String)],
                                      systemDefault: String?) -> String? {
        guard let selectedID else { return systemDefault }
        return available.first { $0.id == selectedID }?.name
    }
}

public enum SettingsChoices {
    public static let standardResolutions = [1280, 1920, 2560, 3840]
    public static let standardFramesPerSecond = [15, 30, 60]

    /// The standard values plus `current` when it is not one of them, ascending.
    public static func resolutions(including current: Int) -> [Int] {
        Set(standardResolutions + [current]).sorted()
    }

    public static func framesPerSecond(including current: Int) -> [Int] {
        Set(standardFramesPerSecond + [current]).sorted()
    }

    public static func resolutionLabel(_ longSide: Int) -> String {
        let names = [1280: "720p", 1920: "1080p", 2560: "1440p", 3840: "4K"]
        guard let name = names[longSide] else { return "\(longSide) px" }
        return "\(longSide) px (\(name))"
    }
}
