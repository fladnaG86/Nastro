import XCTest
@testable import NastroCore

final class CapturePlanTests: XCTestCase {
    // MARK: - Target resolution

    func testMainDisplayResolvesToMain() {
        XCTAssertEqual(CaptureTargets.resolve(.mainDisplay, displayIDs: [1, 2], mainDisplayID: 2, windowIDs: []),
                       .display(id: 2))
    }

    func testSavedDisplayResolvesWhenPresent() {
        XCTAssertEqual(CaptureTargets.resolve(.display(id: 1), displayIDs: [1, 2], mainDisplayID: 2, windowIDs: []),
                       .display(id: 1))
    }

    func testMissingDisplayFallsBackToMain() {
        XCTAssertEqual(CaptureTargets.resolve(.display(id: 9), displayIDs: [1, 2], mainDisplayID: 2, windowIDs: []),
                       .display(id: 2))
    }

    func testWindowResolvesWhenPresent() {
        XCTAssertEqual(CaptureTargets.resolve(.window(id: 7), displayIDs: [1], mainDisplayID: 1, windowIDs: [5, 7]),
                       .window(id: 7))
    }

    func testMissingWindowIsUnavailable() {
        XCTAssertNil(CaptureTargets.resolve(.window(id: 8), displayIDs: [1], mainDisplayID: 1, windowIDs: [5, 7]))
    }

    func testNoDisplayIsUnavailable() {
        XCTAssertNil(CaptureTargets.resolve(.mainDisplay, displayIDs: [], mainDisplayID: 1, windowIDs: []))
        XCTAssertNil(CaptureTargets.resolve(.display(id: 3), displayIDs: [1], mainDisplayID: 2, windowIDs: []))
    }

    // MARK: - Stream layout

    func testDisplaySourceIsOneFullStreamWithAllAudio() {
        let plan = CapturePlanner.streams(mode: .videoAndAudio, target: .display(id: 3), mainDisplayID: 1,
                                          systemAudio: true, microphone: true)
        XCTAssertEqual(plan, [StreamPlan(target: .display(id: 3), video: .full, systemAudio: true, microphone: true)])
    }

    func testWindowSourceSplitsAudioOntoMainDisplayStreamStartedFirst() {
        let plan = CapturePlanner.streams(mode: .videoAndAudio, target: .window(id: 7), mainDisplayID: 1,
                                          systemAudio: true, microphone: false)
        XCTAssertEqual(plan, [
            StreamPlan(target: .display(id: 1), video: .placeholder, systemAudio: true, microphone: false),
            StreamPlan(target: .window(id: 7), video: .full, systemAudio: false, microphone: false),
        ])
    }

    func testWindowSourceWithoutAudioIsOneStream() {
        let plan = CapturePlanner.streams(mode: .videoAndAudio, target: .window(id: 7), mainDisplayID: 1,
                                          systemAudio: false, microphone: false)
        XCTAssertEqual(plan, [StreamPlan(target: .window(id: 7), video: .full, systemAudio: false, microphone: false)])
    }

    func testAudioOnlyIsOnePlaceholderStreamOnMainDisplay() {
        let plan = CapturePlanner.streams(mode: .audioOnly, target: .window(id: 7), mainDisplayID: 1,
                                          systemAudio: true, microphone: true)
        XCTAssertEqual(plan, [StreamPlan(target: .display(id: 1), video: .placeholder, systemAudio: true, microphone: true)])
    }

    // MARK: - Window listing

    private func listable(title: String? = "Doc", layer: Int = 0, width: Double = 800, height: Double = 600,
                          onScreen: Bool = true, ownApp: Bool = false) -> Bool {
        WindowListing.isListable(title: title, layer: layer, width: width, height: height,
                                 isOnScreen: onScreen, isOwnApp: ownApp)
    }

    func testOrdinaryWindowIsListed() { XCTAssertTrue(listable()) }
    func testMinimumSizeIsListed() { XCTAssertTrue(listable(width: 100, height: 100)) }
    func testOffScreenIsNotListed() { XCTAssertFalse(listable(onScreen: false)) }
    func testUntitledIsNotListed() {
        XCTAssertFalse(listable(title: nil))
        XCTAssertFalse(listable(title: ""))
        XCTAssertFalse(listable(title: "   "))
    }
    func testNonZeroLayerIsNotListed() { XCTAssertFalse(listable(layer: 25)) }
    func testSmallIsNotListed() {
        XCTAssertFalse(listable(width: 99, height: 600))
        XCTAssertFalse(listable(width: 800, height: 99.5))
    }
    func testOwnAppIsNotListed() { XCTAssertFalse(listable(ownApp: true)) }
}
