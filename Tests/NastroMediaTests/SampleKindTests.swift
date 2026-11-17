import XCTest
@testable import NastroMedia

final class SampleKindTests: XCTestCase {
    func testVideoSpecEquality() {
        XCTAssertEqual(VideoSpec(width: 1920, height: 1080, fps: 30),
                       VideoSpec(width: 1920, height: 1080, fps: 30))
        XCTAssertNotEqual(VideoSpec(width: 1920, height: 1080, fps: 30),
                          VideoSpec(width: 1920, height: 1080, fps: 60))
    }
}
