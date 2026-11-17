import XCTest
@testable import NastroCore

final class RecorderMachineTests: XCTestCase {
    func testHappyPath() {
        var m = RecorderMachine(); let t = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(m.apply(.startRequested)); XCTAssertEqual(m.state, .starting)
        XCTAssertTrue(m.apply(.started(at: t))); XCTAssertEqual(m.state, .recording(since: t))
        XCTAssertTrue(m.apply(.stopRequested(.user))); XCTAssertEqual(m.state, .finalizing(reason: .user))
        XCTAssertTrue(m.apply(.finalized)); XCTAssertEqual(m.state, .idle)
    }

    func testDoubleStartAndDoubleStopIgnored() {
        var m = RecorderMachine(); _ = m.apply(.startRequested)
        XCTAssertFalse(m.apply(.startRequested))
        _ = m.apply(.started(at: Date())); _ = m.apply(.stopRequested(.user))
        XCTAssertFalse(m.apply(.stopRequested(.sourceLost)))
        XCTAssertEqual(m.state, .finalizing(reason: .user))
        XCTAssertFalse(m.apply(.startRequested))          // no start while finalizing
    }

    func testStopWhileStarting() {
        var m = RecorderMachine(); _ = m.apply(.startRequested)
        XCTAssertTrue(m.apply(.stopRequested(.user))); XCTAssertEqual(m.state, .finalizing(reason: .user))
    }

    func testStartFailedReturnsToIdle() {
        var m = RecorderMachine(); _ = m.apply(.startRequested)
        XCTAssertTrue(m.apply(.startFailed)); XCTAssertEqual(m.state, .idle)
        XCTAssertTrue(m.apply(.startRequested)); XCTAssertEqual(m.state, .starting)
    }

    func testFinalizeFailedReturnsToIdle() {
        var m = RecorderMachine(); _ = m.apply(.startRequested); _ = m.apply(.stopRequested(.diskFull))
        XCTAssertEqual(m.state, .finalizing(reason: .diskFull))
        XCTAssertTrue(m.apply(.finalizeFailed)); XCTAssertEqual(m.state, .idle)
    }

    func testStopWhileIdleIgnored() {
        var m = RecorderMachine()
        XCTAssertFalse(m.apply(.stopRequested(.user))); XCTAssertEqual(m.state, .idle)
        XCTAssertFalse(m.apply(.finalized)); XCTAssertFalse(m.apply(.startFailed))
        XCTAssertFalse(m.apply(.started(at: Date()))); XCTAssertEqual(m.state, .idle)
    }
}
