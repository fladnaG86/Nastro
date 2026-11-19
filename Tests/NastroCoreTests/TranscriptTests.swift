import XCTest
@testable import NastroCore

final class TranscriptTests: XCTestCase {
    func testSiblingNamesKeepSpacesAndSuffix() {
        let rec = URL(fileURLWithPath: "/x/2026-11-18 10.02 Call 2.mp4")
        XCTAssertEqual(SiblingFiles.transcriptURL(for: rec).lastPathComponent, "2026-11-18 10.02 Call 2.trascrizione.txt")
        XCTAssertEqual(SiblingFiles.summaryURL(for: rec).lastPathComponent, "2026-11-18 10.02 Call 2.riassunto.md")
        XCTAssertEqual(SiblingFiles.tempURL(for: SiblingFiles.summaryURL(for: rec)).lastPathComponent,
                       "2026-11-18 10.02 Call 2.riassunto.md.nastro-tmp")
    }

    func testMergeOrdersByStartAcrossSpeakers() {
        let others = [TranscriptSegment(start: 0, end: 2, text: "Buongiorno.", speaker: .others),
                      TranscriptSegment(start: 10, end: 12, text: "Va bene.", speaker: .others)]
        let me = [TranscriptSegment(start: 4, end: 6, text: "Ciao.", speaker: .me)]
        XCTAssertEqual(Transcript.merge([others, me]).map(\.text), ["Buongiorno.", "Ciao.", "Va bene."])
    }

    func testMergeJoinsSameSpeakerWithinTwoSeconds() {
        let s = [TranscriptSegment(start: 0, end: 2, text: "Allora", speaker: .me),
                 TranscriptSegment(start: 3.5, end: 5, text: "partiamo.", speaker: .me),
                 TranscriptSegment(start: 9, end: 10, text: "Ok.", speaker: .me),
                 TranscriptSegment(start: 11, end: 12, text: "  ", speaker: .me)]
        let m = Transcript.merge([s])
        XCTAssertEqual(m.map(\.text), ["Allora partiamo.", "Ok."])
        XCTAssertEqual(m[0].start, 0); XCTAssertEqual(m[0].end, 5)
    }

    func testRenderWithAndWithoutLabels() {
        XCTAssertEqual(Transcript.render([TranscriptSegment(start: 3725, end: 3727, text: "Sì.", speaker: .me)]),
                       "[01:02:05] Io: Sì.\n")
        XCTAssertEqual(Transcript.render([TranscriptSegment(start: 4, end: 5, text: "Ciao.", speaker: nil)]),
                       "[00:00:04] Ciao.\n")
    }

    func testBlankAndSpeakers() {
        XCTAssertTrue(Transcript.isBlank(" \n\t")); XCTAssertFalse(Transcript.isBlank("a"))
        XCTAssertTrue(Transcript.hasSpeakers("[00:00:01] Altri: x\n")); XCTAssertFalse(Transcript.hasSpeakers("[00:00:01] x\n"))
    }

    func testRenderUsesZeroForNonFiniteStart() {
        for start in [Double.nan, .infinity, -.infinity] {
            let text = Transcript.render([TranscriptSegment(start: start, end: 5, text: "ciao", speaker: nil)])
            XCTAssertEqual(text, "[00:00:00] ciao\n")
        }
    }
}
