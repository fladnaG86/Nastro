import XCTest
@testable import NastroCore

final class RecordingRulesTests: XCTestCase {
    private let quiet = AudioSourceFacts(silent: false, samplesStopped: false, notRecorded: false)

    // MARK: warnings

    func testNoWarningsWhenSourcesAreFineOrDisabled() {
        XCTAssertEqual(RecordingRules.warnings(systemAudio: quiet, microphone: quiet), [])
        XCTAssertEqual(RecordingRules.warnings(systemAudio: nil, microphone: nil), [])
    }

    func testSilentSources() {
        let silent = AudioSourceFacts(silent: true, samplesStopped: false, notRecorded: false)
        XCTAssertEqual(RecordingRules.warnings(systemAudio: silent, microphone: quiet), [.systemAudioSilent])
        XCTAssertEqual(RecordingRules.warnings(systemAudio: quiet, microphone: silent), [.microphoneSilent])
        XCTAssertEqual(RecordingRules.warnings(systemAudio: silent, microphone: silent),
                       [.systemAudioSilent, .microphoneSilent])
    }

    func testMicrophoneLostWinsOverSilent() {
        let lost = AudioSourceFacts(silent: true, samplesStopped: true, notRecorded: false)
        XCTAssertEqual(RecordingRules.warnings(systemAudio: quiet, microphone: lost), [.microphoneLost])
    }

    func testNotRecordedWinsOverEverythingElse() {
        let gone = AudioSourceFacts(silent: true, samplesStopped: true, notRecorded: true)
        XCTAssertEqual(RecordingRules.warnings(systemAudio: gone, microphone: gone),
                       [.systemAudioNotRecorded, .microphoneNotRecorded])
    }

    func testDisabledSourceNeverWarns() {
        let gone = AudioSourceFacts(silent: true, samplesStopped: true, notRecorded: true)
        XCTAssertEqual(RecordingRules.warnings(systemAudio: nil, microphone: gone), [.microphoneNotRecorded])
        XCTAssertEqual(RecordingRules.warnings(systemAudio: gone, microphone: nil), [.systemAudioNotRecorded])
    }

    func testSamplesStopped() {
        // Never delivered: not "stopped" (a source that never shows up gets no track instead).
        XCTAssertFalse(RecordingRules.samplesStopped(lastSampleAt: nil, now: 100))
        XCTAssertFalse(RecordingRules.samplesStopped(lastSampleAt: 96, now: 100))
        XCTAssertTrue(RecordingRules.samplesStopped(lastSampleAt: 95, now: 100))
        XCTAssertTrue(RecordingRules.samplesStopped(lastSampleAt: 98, now: 100, grace: 2))
    }

    func testWarningsToNotifyOnlyOncePerRecording() {
        XCTAssertEqual(RecordingRules.warningsToNotify(current: [], alreadyNotified: []), [])
        XCTAssertEqual(RecordingRules.warningsToNotify(current: [.microphoneLost], alreadyNotified: []),
                       [.microphoneLost])
        XCTAssertEqual(RecordingRules.warningsToNotify(current: [.microphoneLost], alreadyNotified: [.microphoneLost]),
                       [])
        // Deterministic order: most serious first.
        XCTAssertEqual(RecordingRules.warningsToNotify(current: [.systemAudioSilent, .microphoneNotRecorded,
                                                                 .microphoneLost],
                                                       alreadyNotified: []),
                       [.microphoneNotRecorded, .microphoneLost, .systemAudioSilent])
    }

    // MARK: start problems

    func testPermissionPreflight() {
        XCTAssertEqual(RecordingRules.permissionProblem(screenGranted: false, microphoneWanted: false,
                                                        microphoneAuthorized: false), .screenPermission)
        XCTAssertEqual(RecordingRules.permissionProblem(screenGranted: false, microphoneWanted: true,
                                                        microphoneAuthorized: false), .screenPermission)
        XCTAssertEqual(RecordingRules.permissionProblem(screenGranted: true, microphoneWanted: true,
                                                        microphoneAuthorized: false), .microphonePermission)
        XCTAssertNil(RecordingRules.permissionProblem(screenGranted: true, microphoneWanted: false,
                                                      microphoneAuthorized: false))
        XCTAssertNil(RecordingRules.permissionProblem(screenGranted: true, microphoneWanted: true,
                                                      microphoneAuthorized: true))
    }

    func testMicrophoneAccessDecision() {
        XCTAssertEqual(RecordingRules.microphoneDecision(wanted: false, access: .denied), .proceed)
        XCTAssertEqual(RecordingRules.microphoneDecision(wanted: false, access: .notDetermined), .proceed)
        XCTAssertEqual(RecordingRules.microphoneDecision(wanted: true, access: .authorized), .proceed)
        XCTAssertEqual(RecordingRules.microphoneDecision(wanted: true, access: .notDetermined), .ask)
        XCTAssertEqual(RecordingRules.microphoneDecision(wanted: true, access: .denied), .fail)
    }

    func testStartProblemForFailure() {
        func problem(_ failure: StartFailure, screen: Bool = true, micWanted: Bool = true,
                     micAuthorized: Bool = true) -> StartProblem {
            RecordingRules.startProblem(for: failure, screenGranted: screen, microphoneWanted: micWanted,
                                        microphoneAuthorized: micAuthorized)
        }
        XCTAssertEqual(problem(.folder), .folder)
        XCTAssertEqual(problem(.sourceUnavailable), .sourceUnavailable)
        XCTAssertEqual(problem(.noFirstFrame), .other)
        XCTAssertEqual(problem(.other), .other)
        XCTAssertEqual(problem(.permissionDenied, screen: false), .screenPermission)
        XCTAssertEqual(problem(.permissionDenied, micAuthorized: false), .microphonePermission)
        XCTAssertEqual(problem(.permissionDenied, micWanted: false, micAuthorized: false), .screenPermission)
        // Both granted yet refused: the user declined the screen capture prompt.
        XCTAssertEqual(problem(.permissionDenied), .screenPermission)
    }

    func testFirstFrameOverdue() {
        XCTAssertFalse(RecordingRules.firstFrameOverdue(expectsVideo: true, sawVideo: false, secondsSinceStart: 4.9))
        XCTAssertTrue(RecordingRules.firstFrameOverdue(expectsVideo: true, sawVideo: false, secondsSinceStart: 5))
        XCTAssertFalse(RecordingRules.firstFrameOverdue(expectsVideo: true, sawVideo: true, secondsSinceStart: 60))
        XCTAssertFalse(RecordingRules.firstFrameOverdue(expectsVideo: false, sawVideo: false, secondsSinceStart: 60))
    }

    // MARK: stop

    func testStopReasonForStreamError() {
        XCTAssertEqual(RecordingRules.stopReason(streamErrorCode: nil), .streamError)
        XCTAssertEqual(RecordingRules.stopReason(streamErrorCode: -3813), .sourceLost)   // no window list
        XCTAssertEqual(RecordingRules.stopReason(streamErrorCode: -3814), .sourceLost)   // no display list
        XCTAssertEqual(RecordingRules.stopReason(streamErrorCode: -3815), .sourceLost)   // no capture source
        XCTAssertEqual(RecordingRules.stopReason(streamErrorCode: -3817), .user)         // stopped from the system UI
        XCTAssertEqual(RecordingRules.stopReason(streamErrorCode: -3822), .diskFull)     // insufficient storage
        XCTAssertEqual(RecordingRules.stopReason(streamErrorCode: -3821), .streamError)  // system stopped stream
        XCTAssertEqual(RecordingRules.stopReason(streamErrorCode: -3811), .streamError)
    }

    func testStopMessage() {
        XCTAssertNil(RecordingRules.stopMessageKey(.user))
        XCTAssertEqual(RecordingRules.stopMessageKey(.sourceLost), .stoppedSourceLost)
        XCTAssertEqual(RecordingRules.stopMessageKey(.streamError), .stoppedStreamError)
        XCTAssertEqual(RecordingRules.stopMessageKey(.diskFull), .stoppedDiskFull)
    }

    func testRoomToFinalize() {
        XCTAssertTrue(RecordingRules.hasRoomToFinalize(freeBytes: 2_000, workFileBytes: 1_000))
        XCTAssertTrue(RecordingRules.hasRoomToFinalize(freeBytes: 1_000, workFileBytes: 1_000))
        XCTAssertFalse(RecordingRules.hasRoomToFinalize(freeBytes: 999, workFileBytes: 1_000))
        // Unknown free space: try anyway (finalization failure keeps the work file).
        XCTAssertTrue(RecordingRules.hasRoomToFinalize(freeBytes: nil, workFileBytes: 1_000))
    }

    // MARK: texts

    func testEveryWarningAndProblemHasItsOwnText() {
        let warnings: [Warning] = [.systemAudioSilent, .microphoneSilent, .microphoneLost,
                                   .systemAudioNotRecorded, .microphoneNotRecorded]
        XCTAssertEqual(Set(warnings.map(\.messageKey)).count, warnings.count)
        let problems: [StartProblem] = [.screenPermission, .microphonePermission, .folder, .sourceUnavailable, .other]
        XCTAssertEqual(Set(problems.map(\.messageKey)).count, problems.count)
    }
}
