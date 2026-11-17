import XCTest
@testable import NastroCore

final class VideoSizingTests: XCTestCase {
    func testSizes() {
        func s(_ w: Int, _ h: Int, _ m: Int) -> [Int] {
            let r = VideoSizing.outputSize(sourceWidth: w, sourceHeight: h, maxLongSide: m); return [r.width, r.height]
        }
        XCTAssertEqual(s(3456, 2234, 1920), [1920, 1240])   // MacBook Pro 16"
        XCTAssertEqual(s(1280, 720, 1920), [1280, 720])     // never upscale
        XCTAssertEqual(s(1081, 1921, 1920), [1080, 1920])   // portrait, even
        XCTAssertEqual(s(801, 601, 1920), [800, 600])       // odd -> even
    }
}
