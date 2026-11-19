import XCTest
@testable import NastroCore

final class SummaryMessagesTests: XCTestCase {
    private let errors: [SummaryError] = [
        .noAudio, .noSpeech, .speechModelUnavailable, .cannotWrite, .invalidURL,
        .modelUnreachable(url: "http://x"), .http(status: 500, detail: "boom"), .http(status: 0, detail: "boom"),
        .emptyReply,
    ]

    func testEveryErrorHasTextInBothLanguages() {
        for language in [L10n.Language.it, .en] {
            for error in errors {
                let text = SummaryMessages.text(error, language: language)
                XCTAssertFalse(text?.isEmpty ?? true, "\(error) \(language)")
            }
        }
    }

    func testCancelledHasNoText() {
        XCTAssertNil(SummaryMessages.text(.cancelled, language: .it))
        XCTAssertNil(SummaryMessages.text(.cancelled, language: .en))
    }

    func testUnreachableNamesTheURL() {
        XCTAssertEqual(SummaryMessages.text(.modelUnreachable(url: "http://x"), language: .it),
                       "Modello non raggiungibile su http://x: server LLM acceso?")
    }

    func testHTTPStatus() {
        XCTAssertEqual(SummaryMessages.text(.http(status: 500, detail: "boom"), language: .it),
                       "Errore 500 dal server: boom")
        // Status 0 = an out-of-contract chat error: no "Errore 0".
        XCTAssertEqual(SummaryMessages.text(.http(status: 0, detail: "boom"), language: .it), "boom")
        XCTAssertEqual(SummaryMessages.text(.http(status: 0, detail: " "), language: .en),
                       "Error from the server.")
    }

    func testPhaseText() {
        XCTAssertEqual(SummaryMessages.phaseText(.preparing, language: .it), "Preparazione…")
        XCTAssertEqual(SummaryMessages.phaseText(.transcribing(0.42), language: .it), "Trascrizione 42%")
        XCTAssertEqual(SummaryMessages.phaseText(.transcribing(0.42), language: .en), "Transcribing 42%")
        XCTAssertEqual(SummaryMessages.phaseText(.summarizing(part: 2, of: 3), language: .it), "Riassunto 2 di 3…")
        XCTAssertEqual(SummaryMessages.phaseText(.summarizing(part: 1, of: 1), language: .it), "Riassunto…")
    }

    func testNonFiniteProgressShowsZeroPercent() {
        XCTAssertEqual(SummaryMessages.phaseText(.transcribing(.nan), language: .it), "Trascrizione 0%")
        XCTAssertEqual(SummaryMessages.phaseText(.transcribing(.infinity), language: .it), "Trascrizione 0%")
    }
}
