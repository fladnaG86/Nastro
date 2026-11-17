import XCTest
@testable import NastroCore

final class L10nTests: XCTestCase {
    func testBothLanguagesHaveEveryKey() {
        for key in L10n.Key.allCases {
            XCTAssertFalse(L10n.t(key, language: .it).isEmpty, "missing it for \(key)")
            XCTAssertFalse(L10n.t(key, language: .en).isEmpty, "missing en for \(key)")
        }
    }

    func testLanguageFromPreferred() {
        XCTAssertEqual(L10n.Language.from(preferred: ["it-IT", "en"]), .it)
        XCTAssertEqual(L10n.Language.from(preferred: ["en-US", "it"]), .en)
        XCTAssertEqual(L10n.Language.from(preferred: []), .en)
    }
}
