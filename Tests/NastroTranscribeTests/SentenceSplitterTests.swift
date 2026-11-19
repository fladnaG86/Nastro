import XCTest
import NastroCore
@testable import NastroTranscribe

final class SentenceSplitterTests: XCTestCase {
    private typealias Word = SentenceSplitter.Word
    private let range = (start: 0.0, end: 30.0)

    func testSplitsAtSentenceEnds() {
        let words = [
            Word(text: "Buongiorno", start: 0.5, end: 1.0), Word(text: " a", start: 1.0, end: 1.1),
            Word(text: " tutti.", start: 1.1, end: 1.6), Word(text: " Come", start: 1.8, end: 2.0),
            Word(text: " va?", start: 2.0, end: 2.4), Word(text: " Bene!", start: 2.6, end: 3.0),
            Word(text: " Allora…", start: 3.2, end: 3.8), Word(text: " ecco", start: 4.0, end: 4.3),
        ]
        let segments = SentenceSplitter.split(words, range: range, speaker: .me)
        XCTAssertEqual(segments, [
            TranscriptSegment(start: 0.5, end: 1.6, text: "Buongiorno a tutti.", speaker: .me),
            TranscriptSegment(start: 1.8, end: 2.4, text: "Come va?", speaker: .me),
            TranscriptSegment(start: 2.6, end: 3.0, text: "Bene!", speaker: .me),
            TranscriptSegment(start: 3.2, end: 3.8, text: "Allora…", speaker: .me),
            TranscriptSegment(start: 4.0, end: 4.3, text: "ecco", speaker: .me),
        ])
    }

    func testSplitsAtPauseOfOneSecond() {
        let words = [
            Word(text: "sì", start: 0.0, end: 0.4), Word(text: " certo", start: 0.5, end: 1.0),
            Word(text: " poi", start: 2.0, end: 2.3), Word(text: " vediamo", start: 2.4, end: 2.9),
            Word(text: " dopo", start: 3.8, end: 4.1),
        ]
        let segments = SentenceSplitter.split(words, range: range, speaker: nil)
        XCTAssertEqual(segments.map(\.text), ["sì certo", "poi vediamo dopo"])
        XCTAssertEqual(segments.map(\.start), [0.0, 2.0])
        XCTAssertEqual(segments.map(\.end), [1.0, 4.1])
    }

    func testMissingTimesFallBackToResultRange() {
        let words = [Word(text: " ciao", start: nil, end: nil), Word(text: " a tutti", start: nil, end: nil)]
        let segments = SentenceSplitter.split(words, range: (start: 5.0, end: 9.0), speaker: .others)
        XCTAssertEqual(segments, [TranscriptSegment(start: 5.0, end: 9.0, text: "ciao a tutti", speaker: .others)])
    }

    func testPartlyMissingTimesUseKnownWords() {
        let words = [Word(text: " uno", start: nil, end: nil), Word(text: " due", start: 6.0, end: 6.5),
                     Word(text: " tre.", start: nil, end: nil)]
        let segments = SentenceSplitter.split(words, range: (start: 5.0, end: 9.0), speaker: nil)
        XCTAssertEqual(segments, [TranscriptSegment(start: 6.0, end: 6.5, text: "uno due tre.", speaker: nil)])
    }

    func testBlankWordsGiveNoSegment() {
        XCTAssertTrue(SentenceSplitter.split([Word(text: "  ", start: 1, end: 2)], range: range, speaker: nil).isEmpty)
        XCTAssertTrue(SentenceSplitter.split([], range: range, speaker: nil).isEmpty)
    }

    func testNonFiniteWordTimesFallBackToResultRange() {
        let words = [Word(text: "Ciao.", start: .nan, end: .infinity)]
        let segments = SentenceSplitter.split(words, range: range, speaker: .me)
        XCTAssertEqual(segments, [TranscriptSegment(start: 0, end: 30, text: "Ciao.", speaker: .me)])
    }
}
