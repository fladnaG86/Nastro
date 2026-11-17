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

    func testDiskGuardKeepsRoomToFinalizeTheWorkFile() {
        // F4: stop below work file + 500 MB, never below the 1 GB floor.
        XCTAssertTrue(DiskGuard.shouldStop(freeBytes: 999_999_999, workFileBytes: 0))
        XCTAssertFalse(DiskGuard.shouldStop(freeBytes: 1_000_000_000, workFileBytes: 100_000_000))
        XCTAssertTrue(DiskGuard.shouldStop(freeBytes: 3_299_999_999, workFileBytes: 2_800_000_000))
        XCTAssertFalse(DiskGuard.shouldStop(freeBytes: 3_300_000_000, workFileBytes: 2_800_000_000))
        // At the moment it stops, there is still room to finalize (a 2-hour call ≈ 2.8 GB).
        let free: Int64 = 3_299_999_999
        XCTAssertTrue(RecordingRules.hasRoomToFinalize(freeBytes: free, workFileBytes: 2_800_000_000))
    }

    func testDiskGuard() {
        XCTAssertTrue(DiskGuard.shouldStop(freeBytes: 999_999_999)); XCTAssertFalse(DiskGuard.shouldStop(freeBytes: 1_000_000_000))
    }
}
