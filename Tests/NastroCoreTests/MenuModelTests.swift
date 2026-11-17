import Carbon.HIToolbox
import XCTest
@testable import NastroCore

final class MenuModelTests: XCTestCase {
    private let since = Date(timeIntervalSince1970: 0)

    // MARK: Menu bar label

    func testLabelIdle() {
        let label = MenuBarLabel.make(state: .idle, elapsedSeconds: 99, attention: false)
        XCTAssertEqual(label, MenuBarLabel(symbol: "record.circle", isRed: false, elapsed: nil, showsWarning: false))
    }

    func testLabelStartingLooksIdle() {
        XCTAssertEqual(MenuBarLabel.make(state: .starting, elapsedSeconds: 0, attention: false).symbol, "record.circle")
    }

    func testLabelRecordingShowsRedDotAndTime() {
        let label = MenuBarLabel.make(state: .recording(since: since), elapsedSeconds: 754, attention: false)
        XCTAssertEqual(label, MenuBarLabel(symbol: "record.circle.fill", isRed: true, elapsed: "12:34", showsWarning: false))
    }

    func testLabelFinalizingShowsHourglass() {
        let label = MenuBarLabel.make(state: .finalizing(reason: .user), elapsedSeconds: 754, attention: false)
        XCTAssertEqual(label, MenuBarLabel(symbol: "hourglass", isRed: false, elapsed: nil, showsWarning: false))
    }

    func testLabelAddsWarningTriangle() {
        XCTAssertTrue(MenuBarLabel.make(state: .recording(since: since), elapsedSeconds: 1, attention: true).showsWarning)
        XCTAssertTrue(MenuBarLabel.make(state: .idle, elapsedSeconds: 0, attention: true).showsWarning)
        XCTAssertEqual(MenuBarLabel.warningSymbol, "exclamationmark.triangle.fill")
    }

    func testAttentionFromWarningsOrProblem() {
        XCTAssertFalse(MenuBarLabel.needsAttention(warnings: [], problem: nil))
        XCTAssertTrue(MenuBarLabel.needsAttention(warnings: [.microphoneSilent], problem: nil))
        XCTAssertTrue(MenuBarLabel.needsAttention(warnings: [], problem: .screenPermission))
    }

    // MARK: Sections

    func testIdleSectionsInSpecOrder() {
        XCTAssertEqual(MenuLayout.sections(state: .idle, mode: .videoAndAudio, problem: nil),
                       [.start, .mode, .videoSource, .audio, .openFolder, .settings, .quit])
    }

    func testAudioOnlyHidesVideoSource() {
        XCTAssertEqual(MenuLayout.sections(state: .idle, mode: .audioOnly, problem: nil),
                       [.start, .mode, .audio, .openFolder, .settings, .quit])
    }

    func testProblemRowComesFirst() {
        XCTAssertEqual(MenuLayout.sections(state: .idle, mode: .audioOnly, problem: .folder).first, .problem)
    }

    func testStartingKeepsIdleRowsButNotEditable() {
        XCTAssertEqual(MenuLayout.sections(state: .starting, mode: .videoAndAudio, problem: nil),
                       MenuLayout.sections(state: .idle, mode: .videoAndAudio, problem: nil))
        XCTAssertTrue(MenuLayout.choicesEditable(.idle))
        XCTAssertFalse(MenuLayout.choicesEditable(.starting))
        XCTAssertFalse(MenuLayout.choicesEditable(.recording(since: since)))
        XCTAssertTrue(MenuLayout.startEnabled(.idle))
        XCTAssertFalse(MenuLayout.startEnabled(.starting))
    }

    func testRecordingHasNoSourceChoicesAndNoQuit() {
        XCTAssertEqual(MenuLayout.sections(state: .recording(since: since), mode: .videoAndAudio, problem: .folder),
                       [.stop, .meters, .openFolder, .settings])
    }

    func testFinalizingShowsPreparing() {
        XCTAssertEqual(MenuLayout.sections(state: .finalizing(reason: .user), mode: .videoAndAudio, problem: nil),
                       [.preparing, .openFolder, .settings])
    }

    func testDisplayedProblem() {
        XCTAssertNil(MenuLayout.displayedProblem(startProblem: nil, screenGranted: true))
        XCTAssertEqual(MenuLayout.displayedProblem(startProblem: nil, screenGranted: false), .screenPermission)
        XCTAssertEqual(MenuLayout.displayedProblem(startProblem: .folder, screenGranted: false), .folder)
    }

    func testPermissionPane() {
        XCTAssertEqual(MenuLayout.permissionPane(for: .screenPermission), .screen)
        XCTAssertEqual(MenuLayout.permissionPane(for: .microphonePermission), .microphone)
        XCTAssertNil(MenuLayout.permissionPane(for: .folder))
        XCTAssertNil(MenuLayout.permissionPane(for: .sourceUnavailable))
        XCTAssertNil(MenuLayout.permissionPane(for: .other))
    }

    // MARK: Meters and warnings

    func testMeterFraction() {
        XCTAssertEqual(LevelMeter.fraction(0), 1)
        XCTAssertEqual(LevelMeter.fraction(-60), 0)
        XCTAssertEqual(LevelMeter.fraction(-30), 0.5, accuracy: 1e-9)
        XCTAssertEqual(LevelMeter.fraction(-12), 0.8, accuracy: 1e-6)
        XCTAssertEqual(LevelMeter.fraction(-100), 0)
        XCTAssertEqual(LevelMeter.fraction(6), 1)
        XCTAssertEqual(LevelMeter.fraction(.nan), 0)
    }

    func testWarningsPerChannel() {
        let all: Set<Warning> = [.systemAudioSilent, .microphoneSilent, .microphoneLost,
                                 .systemAudioNotRecorded, .microphoneNotRecorded]
        XCTAssertEqual(MeterWarnings.for(.system, in: all), [.systemAudioNotRecorded, .systemAudioSilent])
        XCTAssertEqual(MeterWarnings.for(.microphone, in: all),
                       [.microphoneNotRecorded, .microphoneLost, .microphoneSilent])
        XCTAssertEqual(MeterWarnings.for(.microphone, in: [.systemAudioSilent]), [])
    }

    func testCriticalWarnings() {
        XCTAssertTrue(MeterWarnings.isCritical(.systemAudioNotRecorded))
        XCTAssertTrue(MeterWarnings.isCritical(.microphoneNotRecorded))
        XCTAssertFalse(MeterWarnings.isCritical(.microphoneLost))
        XCTAssertFalse(MeterWarnings.isCritical(.microphoneSilent))
        XCTAssertFalse(MeterWarnings.isCritical(.systemAudioSilent))
    }

    // MARK: Hotkey

    func testAllowedLettersExcludeReserved() {
        XCTAssertEqual(HotKeyLetters.allowed.count, 23)
        XCTAssertEqual(HotKeyLetters.allowed.first, "A")
        XCTAssertEqual(HotKeyLetters.allowed.last, "Z")
        for reserved in ["S", "R", "T"] { XCTAssertFalse(HotKeyLetters.allowed.contains(reserved)) }
        XCTAssertTrue(HotKeyLetters.allowed.contains("N"))
    }

    func testKeyCodesMatchCarbon() {
        let carbon: [String: Int] = [
            "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E,
            "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J,
            "K": kVK_ANSI_K, "L": kVK_ANSI_L, "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O,
            "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W,
            "X": kVK_ANSI_X, "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
        ]
        for letter in HotKeyLetters.allowed { XCTAssertEqual(HotKeyLetters.keyCode(for: letter), carbon[letter], letter) }
        XCTAssertEqual(HotKeyLetters.keyCode(for: "n"), kVK_ANSI_N)
    }

    func testReservedOrInvalidLettersHaveNoKeyCode() {
        for letter in ["S", "R", "T", "s", "", "NN", "1", "é"] { XCTAssertNil(HotKeyLetters.keyCode(for: letter), letter) }
    }

    func testModifiersAreControlOption() {
        XCTAssertEqual(HotKeyLetters.modifiers, controlKey | optionKey)
        XCTAssertEqual(HotKeyLetters.display("N"), "⌃⌥N")
    }

    // MARK: Sources

    func testWindowLabel() {
        XCTAssertEqual(SourceChoice.windowLabel(app: "Safari", title: "Apple"), "Safari — Apple")
        XCTAssertEqual(SourceChoice.windowLabel(app: "", title: "Apple"), "Apple")
        XCTAssertEqual(SourceChoice.windowLabel(app: "Safari", title: "  "), "Safari")
    }

    func testDisplayChoice() {
        XCTAssertEqual(SourceChoice.source(forDisplay: 7, isMain: true), .mainDisplay)
        XCTAssertEqual(SourceChoice.source(forDisplay: 8, isMain: false), .display(id: 8))
    }

    // Displays 1 (main) and 2; window 3.
    private func selection(_ saved: VideoSource) -> VideoSource {
        SourceChoice.pickerSelection(saved: saved, displays: [(id: 1, isMain: true), (id: 2, isMain: false)],
                                     windowIDs: [3])
    }

    func testPickerSelectionSavedMain() { XCTAssertEqual(selection(.mainDisplay), .mainDisplay) }

    func testPickerSelectionSavedDisplayThatIsNowMain() { XCTAssertEqual(selection(.display(id: 1)), .mainDisplay) }

    func testPickerSelectionSavedSecondaryDisplay() { XCTAssertEqual(selection(.display(id: 2)), .display(id: 2)) }

    func testPickerSelectionSavedDisplayGone() { XCTAssertEqual(selection(.display(id: 9)), .mainDisplay) }

    func testPickerSelectionSavedWindowGone() { XCTAssertEqual(selection(.window(id: 9)), .mainDisplay) }

    func testPickerSelectionSavedWindowExists() { XCTAssertEqual(selection(.window(id: 3)), .window(id: 3)) }

    func testPickerSelectionAlwaysMatchesAnEntry() {
        // Entries: the main display as `.mainDisplay`, other displays by id, windows by id.
        let entries: Set<VideoSource> = [.mainDisplay, .display(id: 2), .window(id: 3)]
        for saved: VideoSource in [.mainDisplay, .display(id: 1), .display(id: 2), .display(id: 9),
                                   .window(id: 3), .window(id: 9)] {
            XCTAssertTrue(entries.contains(selection(saved)), "\(saved)")
        }
    }

    // MARK: Stale saved source

    func testStaleWindowWhileIdleFallsBackToMainDisplay() {
        XCTAssertEqual(SourceChoice.sourceToSave(saved: .window(id: 9), windowIDs: [3], state: .idle), .mainDisplay)
    }

    func testStaleWindowWhileRecordingIsLeftAlone() {
        XCTAssertNil(SourceChoice.sourceToSave(saved: .window(id: 9), windowIDs: [3], state: .recording(since: since)))
        XCTAssertNil(SourceChoice.sourceToSave(saved: .window(id: 9), windowIDs: [3], state: .starting))
        XCTAssertNil(SourceChoice.sourceToSave(saved: .window(id: 9), windowIDs: [3], state: .finalizing(reason: .user)))
    }

    func testExistingWindowIsLeftAlone() {
        XCTAssertNil(SourceChoice.sourceToSave(saved: .window(id: 3), windowIDs: [3], state: .idle))
    }

    func testStaleDisplayIsLeftAlone() {
        XCTAssertNil(SourceChoice.sourceToSave(saved: .display(id: 9), windowIDs: [3], state: .idle))
    }

    func testMainDisplayIsLeftAlone() {
        XCTAssertNil(SourceChoice.sourceToSave(saved: .mainDisplay, windowIDs: [3], state: .idle))
    }

    func testUnknownWindowListLeavesWindowAlone() {
        // No screen access: the window list could not be loaded, so nothing is known to be gone.
        XCTAssertNil(SourceChoice.sourceToSave(saved: .window(id: 9), windowIDs: nil, state: .idle))
    }

    // MARK: Hotkey outcome

    func testShortcutShownOnlyWhenRegistered() {
        XCTAssertEqual(HotKeyLetters.shortcutBadge(.registered("N")), "⌃⌥N")
        XCTAssertNil(HotKeyLetters.shortcutBadge(.inUse("N")))
        XCTAssertNil(HotKeyLetters.shortcutBadge(.notRegistered))
    }

    func testConflictShownOnlyWhenInUse() {
        XCTAssertEqual(HotKeyLetters.conflict(.inUse("M")), "⌃⌥M")
        XCTAssertNil(HotKeyLetters.conflict(.registered("M")))
        XCTAssertNil(HotKeyLetters.conflict(.notRegistered))
    }

    func testOutcomeFromRegistration() {
        XCTAssertEqual(HotKeyLetters.outcome(letter: "N", registered: true), .registered("N"))
        XCTAssertEqual(HotKeyLetters.outcome(letter: "N", registered: false), .inUse("N"))
        XCTAssertEqual(HotKeyLetters.outcome(letter: "S", registered: false), .notRegistered)
    }

    func testIdleSectionsShowHotKeyConflictAfterProblem() {
        XCTAssertEqual(MenuLayout.sections(state: .idle, mode: .audioOnly, problem: .folder, hotKeyConflict: true),
                       [.problem, .hotKeyConflict, .start, .mode, .audio, .openFolder, .settings, .quit])
        XCTAssertEqual(MenuLayout.sections(state: .recording(since: since), mode: .audioOnly, problem: nil,
                                           hotKeyConflict: true),
                       [.hotKeyConflict, .stop, .meters, .openFolder, .settings])
        XCTAssertEqual(MenuLayout.sections(state: .finalizing(reason: .user), mode: .audioOnly, problem: nil,
                                           hotKeyConflict: true),
                       [.hotKeyConflict, .preparing, .openFolder, .settings])
    }

    // MARK: Settings lock

    func testNextRecordingSettingsLockedUnlessIdle() {
        XCTAssertFalse(SettingsLock.isLocked(.idle))
        XCTAssertTrue(SettingsLock.isLocked(.starting))
        XCTAssertTrue(SettingsLock.isLocked(.recording(since: since)))
        XCTAssertTrue(SettingsLock.isLocked(.finalizing(reason: .user)))
    }

    // MARK: Problem row

    func testScreenPermissionRowAsksForRelaunchAndOffersQuit() {
        XCTAssertEqual(MenuLayout.problemRow(for: .screenPermission),
                       ProblemRow(pane: .screen, needsRelaunch: true))
    }

    func testOtherProblemRows() {
        XCTAssertEqual(MenuLayout.problemRow(for: .microphonePermission), ProblemRow(pane: .microphone, needsRelaunch: false))
        XCTAssertEqual(MenuLayout.problemRow(for: .folder), ProblemRow(pane: nil, needsRelaunch: false))
        XCTAssertEqual(MenuLayout.problemRow(for: .other), ProblemRow(pane: nil, needsRelaunch: false))
    }

    func testMicrophoneName() {
        let mics = [("a", "MacBook Pro Microphone"), ("b", "BlackHole 2ch")]
        XCTAssertEqual(SourceChoice.microphoneName(selectedID: nil, available: mics, systemDefault: "Default"), "Default")
        XCTAssertEqual(SourceChoice.microphoneName(selectedID: "b", available: mics, systemDefault: "Default"), "BlackHole 2ch")
        XCTAssertNil(SourceChoice.microphoneName(selectedID: "zz", available: mics, systemDefault: "Default"))
        XCTAssertNil(SourceChoice.microphoneName(selectedID: nil, available: mics, systemDefault: nil))
    }

    // MARK: Settings choices

    func testResolutionAndFpsOptions() {
        XCTAssertEqual(SettingsChoices.resolutions(including: 1920), [1280, 1920, 2560, 3840])
        XCTAssertEqual(SettingsChoices.resolutions(including: 1000), [1000, 1280, 1920, 2560, 3840])
        XCTAssertEqual(SettingsChoices.framesPerSecond(including: 30), [15, 30, 60])
        XCTAssertEqual(SettingsChoices.framesPerSecond(including: 24), [15, 24, 30, 60])
    }

    func testResolutionLabel() {
        XCTAssertEqual(SettingsChoices.resolutionLabel(1280), "1280 px (720p)")
        XCTAssertEqual(SettingsChoices.resolutionLabel(1920), "1920 px (1080p)")
        XCTAssertEqual(SettingsChoices.resolutionLabel(2560), "2560 px (1440p)")
        XCTAssertEqual(SettingsChoices.resolutionLabel(3840), "3840 px (4K)")
        XCTAssertEqual(SettingsChoices.resolutionLabel(1000), "1000 px")
    }
}
