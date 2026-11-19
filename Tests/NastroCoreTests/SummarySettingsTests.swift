import XCTest
@testable import NastroCore

final class SummarySettingsTests: XCTestCase {
    private var suites: [String] = []

    private func makeDefaults() -> UserDefaults {
        let name = "nastro-test-\(UUID())"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    override func tearDown() {
        for n in suites { UserDefaults().removePersistentDomain(forName: n) }
        suites = []
        super.tearDown()
    }

    func testDefaultsAndLocal() {
        XCTAssertTrue(SummarySettings.default.isLocal)
        XCTAssertEqual(SummarySettings.default.model, "gemma-4-26b-a4b")
        XCTAssertEqual(SummarySettings.default.chatCompletionsURL?.absoluteString, "http://127.0.0.1:8001/v1/chat/completions")
        XCTAssertFalse(SummarySettings(baseURL: "https://api.example.com/v1", model: "m").isLocal)
        let full = SummarySettings(baseURL: "http://localhost:11434/v1/chat/completions", model: "m")
        XCTAssertTrue(full.isLocal)
        XCTAssertEqual(full.chatCompletionsURL?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertNil(SummarySettings(baseURL: "not a url", model: "m").chatCompletionsURL)
        XCTAssertNil(SummarySettings(baseURL: "ftp://host/v1", model: "m").chatCompletionsURL)
    }

    func testStoreRoundTripLeavesRecordingSettingsAlone() {
        let d = makeDefaults()
        let store = SummarySettingsStore(defaults: d)
        let custom = SummarySettings(baseURL: "https://api.example.com/v1", model: "big")
        store.save(custom)
        XCTAssertEqual(store.load(), custom)
        XCTAssertNil(d.data(forKey: "settings"))
        XCTAssertNotNil(d.data(forKey: "summarySettings"))
    }

    func testEmptyFieldsFallBackToDefaults() {
        let store = SummarySettingsStore(defaults: makeDefaults())
        store.save(SummarySettings(baseURL: "  ", model: ""))
        XCTAssertEqual(store.load(), .default)
    }
}
