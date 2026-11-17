import XCTest
@testable import NastroCore

final class FileNamingTests: XCTestCase {
    let rome = TimeZone(identifier: "Europe/Rome")!
    var date: Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = rome
        return cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 14, minute: 30, second: 59))!
    }

    func testBaseName() {
        XCTAssertEqual(FileNaming.baseName(date: date, timeZone: rome), "2026-11-17 14.30 Call")
    }

    func testFinalURLExtensionAndDuplicates() {
        let f = URL(fileURLWithPath: "/tmp/x")
        XCTAssertEqual(FileNaming.finalURL(folder: f, date: date, timeZone: rome, hasVideo: true) { _ in false }.lastPathComponent,
                       "2026-11-17 14.30 Call.mp4")
        XCTAssertEqual(FileNaming.finalURL(folder: f, date: date, timeZone: rome, hasVideo: false) { _ in false }.lastPathComponent,
                       "2026-11-17 14.30 Call.m4a")
        let taken: Set = ["2026-11-17 14.30 Call.mp4", "2026-11-17 14.30 Call 2.mp4"]
        XCTAssertEqual(FileNaming.finalURL(folder: f, date: date, timeZone: rome, hasVideo: true) { taken.contains($0.lastPathComponent) }.lastPathComponent,
                       "2026-11-17 14.30 Call 3.mp4")
    }

    func testWorkFileRoundTrip() {
        let final = URL(fileURLWithPath: "/tmp/x/2026-11-17 14.30 Call.mp4")
        let work = FileNaming.workURL(forFinal: final)
        XCTAssertEqual(work.lastPathComponent, "2026-11-17 14.30 Call.nastro-partial.mov")
        XCTAssertEqual(work.deletingLastPathComponent().path, "/tmp/x")
        XCTAssertTrue(FileNaming.isWorkFile(work)); XCTAssertFalse(FileNaming.isWorkFile(final))
        XCTAssertEqual(FileNaming.finalURL(forWorkFile: work, hasVideo: false) { _ in false }.lastPathComponent,
                       "2026-11-17 14.30 Call.m4a")
    }

    func testFinalURLForWorkFileAvoidsDuplicates() {
        let work = URL(fileURLWithPath: "/tmp/x/2026-11-17 14.30 Call.nastro-partial.mov")
        let r = FileNaming.finalURL(forWorkFile: work, hasVideo: true) { $0.lastPathComponent == "2026-11-17 14.30 Call.mp4" }
        XCTAssertEqual(r.lastPathComponent, "2026-11-17 14.30 Call 2.mp4")
    }

    func testPrepareCreatesFolder() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("nastro-test-\(UUID())")
        let folder = base.appendingPathComponent("a/b")
        defer { try? FileManager.default.removeItem(at: base) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        try Destination.prepare(folder)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testPrepareFailsOnUnwritableParent() {
        XCTAssertThrowsError(try Destination.prepare(URL(fileURLWithPath: "/System/Nastro-test"))) {
            XCTAssertEqual($0 as? DestinationError, .cannotCreate)
        }
    }
}
