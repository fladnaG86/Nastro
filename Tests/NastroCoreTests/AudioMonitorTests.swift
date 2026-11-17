import XCTest
@testable import NastroCore

final class AudioMonitorTests: XCTestCase {
    private func peak(_ a: [Float]) -> Float {
        a.withUnsafeBufferPointer { AudioLevel.peakDB($0) }
    }

    func testPeakDB() {
        XCTAssertEqual(peak([0, 0.5, -1.0]), 0, accuracy: 0.01)
        XCTAssertEqual(peak([0.1]), -20, accuracy: 0.01)
        XCTAssertEqual(peak([0, 0, 0]), -100)
        XCTAssertEqual(peak([]), -100)
    }

    func testSilence() {
        var d = SilenceDetector(); d.start(at: 0)
        XCTAssertFalse(d.isSilent(at: 4.9)); XCTAssertTrue(d.isSilent(at: 5))      // nothing ever arrived
        d.feed(levelDB: -80, at: 6); XCTAssertTrue(d.isSilent(at: 6))              // below threshold does not count
        d.feed(levelDB: -20, at: 7); XCTAssertFalse(d.isSilent(at: 11.9)); XCTAssertTrue(d.isSilent(at: 12))
    }

    func testDiskGuard() {
        XCTAssertTrue(DiskGuard.shouldStop(freeBytes: 999_999_999)); XCTAssertFalse(DiskGuard.shouldStop(freeBytes: 1_000_000_000))
    }
}
