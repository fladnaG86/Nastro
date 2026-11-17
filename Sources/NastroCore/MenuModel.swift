import Foundation

/// What the menu bar item shows.
public struct MenuBarLabel: Equatable, Sendable {
    public static let warningSymbol = "exclamationmark.triangle.fill"
    public static let criticalSymbol = "xmark.octagon.fill"

    public var symbol: String
    public var isRed: Bool
    /// Running time, only while recording.
    public var elapsed: String?
    /// Adds `warningSymbol` next to the main symbol.
    public var showsWarning: Bool
    /// Adds the red `criticalSymbol` next to the main symbol.
    public var showsCritical: Bool

    public init(symbol: String, isRed: Bool, elapsed: String?, showsWarning: Bool, showsCritical: Bool = false) {
        self.symbol = symbol
        self.isRed = isRed
        self.elapsed = elapsed
        self.showsWarning = showsWarning
        self.showsCritical = showsCritical
    }

    public static func make(state: RecorderState, elapsedSeconds: Int, attention: Bool,
                            critical: Bool = false) -> MenuBarLabel {
        switch state {
        case .idle, .starting:
            return MenuBarLabel(symbol: "record.circle", isRed: false, elapsed: nil, showsWarning: attention,
                                showsCritical: critical)
        case .recording:
            return MenuBarLabel(symbol: "record.circle.fill", isRed: true,
                                elapsed: TimeFormat.elapsed(elapsedSeconds), showsWarning: attention,
                                showsCritical: critical)
        case .finalizing:
            return MenuBarLabel(symbol: "hourglass", isRed: false, elapsed: nil, showsWarning: attention,
                                showsCritical: critical)
        }
    }

    /// A problem the menu explains (for example a missing permission). Warnings never raise the
    /// triangle: silence is most of a call, critical warnings have their own state
    /// (`isCritical(warnings:)`), and the others stay in the panel. `warnings` is kept for
    /// callers written before that rule.
    public static func needsAttention(warnings: Set<Warning>, problem: StartProblem?) -> Bool {
        problem != nil
    }

    /// A voice is not being recorded: the menu bar shows the red `criticalSymbol`.
    public static func isCritical(warnings: Set<Warning>) -> Bool {
        warnings.contains(where: \.isCritical)
    }
}

/// A block of rows in the menu panel.
public enum MenuSection: Equatable, Sendable {
    case problem, hotKeyConflict, start, mode, videoSource, audio
    case stop, meters, preparing
    case openFolder, settings, quit
}

/// A System Settings privacy pane.
public enum PermissionPane: Equatable, Sendable { case screen, microphone }

/// How the problem row explains and fixes a start problem.
public struct ProblemRow: Equatable, Sendable {
    /// The System Settings pane its button opens; nil = no button.
    public var pane: PermissionPane?
    /// macOS reports a newly granted permission only after a relaunch: the row says so and
    /// offers Quit.
    public var needsRelaunch: Bool

    public init(pane: PermissionPane?, needsRelaunch: Bool) {
        self.pane = pane
        self.needsRelaunch = needsRelaunch
    }
}

public enum MenuLayout {
    /// The rows to show, in order. While recording or preparing the file there are no source
    /// choices and no Quit (quitting would cut the file short).
    public static func sections(state: RecorderState, mode: RecordingMode, problem: StartProblem?,
                                hotKeyConflict: Bool = false) -> [MenuSection] {
        var rows: [MenuSection] = []
        switch state {
        case .idle, .starting:
            if problem != nil { rows.append(.problem) }
            if hotKeyConflict { rows.append(.hotKeyConflict) }
            rows += [.start, .mode]
            if mode == .videoAndAudio { rows.append(.videoSource) }
            rows += [.audio, .openFolder, .settings, .quit]
        case .recording:
            if hotKeyConflict { rows.append(.hotKeyConflict) }
            rows += [.stop, .meters, .openFolder, .settings]
        case .finalizing:
            if hotKeyConflict { rows.append(.hotKeyConflict) }
            rows += [.preparing, .openFolder, .settings]
        }
        return rows
    }

    public static func problemRow(for problem: StartProblem) -> ProblemRow {
        ProblemRow(pane: permissionPane(for: problem), needsRelaunch: problem == .screenPermission)
    }

    public static func choicesEditable(_ state: RecorderState) -> Bool { state == .idle }

    /// Whether an audio source's checkbox can change: in audio-only mode the only enabled
    /// source cannot be unchecked (there would be nothing to record).
    public static func canToggleAudioSource(_ channel: AudioChannel, mode: RecordingMode,
                                            systemAudio: Bool, microphone: Bool) -> Bool {
        guard mode == .audioOnly else { return true }
        switch channel {
        case .system: return !(systemAudio && !microphone)
        case .microphone: return !(microphone && !systemAudio)
        }
    }

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

    /// A voice is missing from the file: must be impossible to miss (same rule as the menu bar).
    public static func isCritical(_ warning: Warning) -> Bool { warning.isCritical }

    /// Warnings shown as their own rows in the recording panel, not under a meter.
    public static func panelRows(in warnings: Set<Warning>) -> [Warning] {
        [Warning.audioDropouts].filter(warnings.contains)
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

    /// What registering `letter` led to. A letter that is not allowed is never registered.
    public static func outcome(letter: String, registered: Bool) -> HotKeyOutcome {
        guard keyCode(for: letter) != nil else { return .notRegistered }
        return registered ? .registered(letter.uppercased()) : .inUse(letter.uppercased())
    }

    /// The shortcut shown next to Start/Stop: only one that actually works.
    public static func shortcutBadge(_ outcome: HotKeyOutcome) -> String? {
        if case .registered(let letter) = outcome { return display(letter) }
        return nil
    }

    /// The shortcut another app holds, for the "in use" row.
    public static func conflict(_ outcome: HotKeyOutcome) -> String? {
        if case .inUse(let letter) = outcome { return display(letter) }
        return nil
    }
}

/// The result of the last hotkey registration.
public enum HotKeyOutcome: Equatable, Sendable {
    case registered(String)
    /// The system refused it, typically because another app holds the shortcut.
    case inUse(String)
    case notRegistered
}

/// Settings that only take effect on the next recording are locked unless idle.
public enum SettingsLock {
    public static func isLocked(_ state: RecorderState) -> Bool { state != .idle }
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

    /// The picker entry to show for the saved source. Entries are the main display as
    /// `.mainDisplay`, other displays by id and windows by id. A saved display that is now the
    /// main one, or a saved display that is gone, shows as the main display (the capture falls
    /// back to it for a missing display). A gone window also shows as the main display, but the
    /// capture does not fall back for windows: `sourceToSave` rewrites such a setting when the
    /// panel reloads, so the picker and the next recording agree.
    public static func pickerSelection(saved: VideoSource, displays: [(id: UInt32, isMain: Bool)],
                                       windowIDs: [UInt32]) -> VideoSource {
        switch saved {
        case .mainDisplay:
            return .mainDisplay
        case .display(let id):
            guard let display = displays.first(where: { $0.id == id }), !display.isMain else { return .mainDisplay }
            return saved
        case .window(let id):
            return windowIDs.contains(id) ? saved : .mainDisplay
        }
    }

    /// The source to store after the panel reloaded its lists, or nil to leave the setting
    /// alone. A saved window that is gone becomes `.mainDisplay` while idle (window ids do not
    /// survive their app closing, and the capture has no fallback for a missing window).
    /// Displays are left alone (the capture falls back to the main one), as is everything while
    /// a recording runs or when the window list is unknown (`windowIDs` nil, no screen access).
    public static func sourceToSave(saved: VideoSource, windowIDs: [UInt32]?, state: RecorderState) -> VideoSource? {
        guard state == .idle, case .window(let id) = saved, let windowIDs, !windowIDs.contains(id) else { return nil }
        return .mainDisplay
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
