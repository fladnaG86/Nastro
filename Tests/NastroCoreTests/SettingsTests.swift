import XCTest
@testable import NastroCore

final class SettingsTests: XCTestCase {
    func testDefaults() {
        let s = Settings.default
        XCTAssertEqual(s.mode, .videoAndAudio); XCTAssertEqual(s.videoSource, .mainDisplay)
        XCTAssertTrue(s.systemAudio); XCTAssertTrue(s.microphone)
        XCTAssertEqual(s.maxLongSide, 1920); XCTAssertEqual(s.fps, 30)
        XCTAssertFalse(s.keepSeparateTracks); XCTAssertEqual(s.hotKeyLetter, "N")
        XCTAssertEqual(s.outputFolder.lastPathComponent, "Nastro")
    }

    func testValidationClampsAndProtectsPostinoKeys() {
        var s = Settings.default; s.fps = 500; s.maxLongSide = 10; s.hotKeyLetter = "R"
        let v = s.validated()
        XCTAssertEqual(v.fps, 60); XCTAssertEqual(v.maxLongSide, 640); XCTAssertEqual(v.hotKeyLetter, "N")
    }

    func testValidationHotKeyLetters() {
        for bad in ["S", "T", "s", "1", "", "NN", "é"] {
            var s = Settings.default; s.hotKeyLetter = bad
            XCTAssertEqual(s.validated().hotKeyLetter, "N", "letter \(bad)")
        }
        var s = Settings.default; s.hotKeyLetter = "k"
        XCTAssertEqual(s.validated().hotKeyLetter, "K")
        s.fps = 1; s.maxLongSide = 99999
        XCTAssertEqual(s.validated().fps, 5); XCTAssertEqual(s.validated().maxLongSide, 3840)
    }

    func testAudioOnlyNeedsOneSource() {
        var s = Settings.default; s.mode = .audioOnly; s.systemAudio = false; s.microphone = false
        XCTAssertTrue(s.validated().systemAudio)
    }

    func testStoreRoundTripAndCorruptData() {
        let d = UserDefaults(suiteName: "nastro-test-\(UUID())")!
        let store = SettingsStore(defaults: d)
        XCTAssertEqual(store.load(), .default)
        var s = Settings.default; s.mode = .audioOnly; s.videoSource = .window(id: 42)
        store.save(s); XCTAssertEqual(store.load(), s)
        d.set(Data([1, 2, 3]), forKey: "settings"); XCTAssertEqual(store.load(), .default)
    }
}
