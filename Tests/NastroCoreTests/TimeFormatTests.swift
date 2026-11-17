import XCTest
@testable import NastroCore

final class TimeFormatTests: XCTestCase {
    func testElapsed() {
        XCTAssertEqual(TimeFormat.elapsed(0), "0:00"); XCTAssertEqual(TimeFormat.elapsed(754), "12:34")
        XCTAssertEqual(TimeFormat.elapsed(3723), "1:02:03")
    }
}
