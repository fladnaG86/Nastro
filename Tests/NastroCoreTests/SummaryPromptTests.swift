import XCTest
@testable import NastroCore

final class SummaryPromptTests: XCTestCase {
    func testShortTranscriptIsOneChunk() { XCTAssertEqual(SummaryPrompt.chunks("a\nb\n").count, 1) }

    func testLongTranscriptSplitsOnLines() {
        let line = String(repeating: "x", count: 999) + "\n"
        let text = String(repeating: line, count: 200)            // 200_000 chars
        let parts = SummaryPrompt.chunks(text)
        XCTAssertEqual(parts.count, 3)
        XCTAssertTrue(parts.allSatisfy { $0.count <= SummaryPrompt.chunkChars && $0.hasSuffix("\n") })
        XCTAssertEqual(parts.joined(), text)
    }

    func testOverLongLineIsCutHard() {
        let text = String(repeating: "y", count: 200_000)
        let parts = SummaryPrompt.chunks(text)
        XCTAssertTrue(parts.count >= 3)
        XCTAssertTrue(parts.allSatisfy { $0.count <= SummaryPrompt.chunkChars })
        XCTAssertEqual(parts.joined(), text)
    }

    func testPromptHasHeadingsRulesAndTranscript() {
        let m = SummaryPrompt.summaryMessages(transcript: "[00:00:01] Io: Ciao.\n", hasSpeakers: true)
        XCTAssertEqual(m.map(\.role), ["system", "user"])
        for h in ["## Di cosa si è parlato", "## Decisioni", "## Cose da fare", "Nessuna"] { XCTAssertTrue(m[0].content.contains(h)) }
        XCTAssertTrue(m[0].content.contains("Altri"))
        XCTAssertTrue(m[1].content.contains("[00:00:01] Io: Ciao."))
        XCTAssertFalse(SummaryPrompt.summaryMessages(transcript: "x", hasSpeakers: false)[0].content.contains("Altri"))
    }

    func testPartAndMergeMessages() {
        XCTAssertTrue(SummaryPrompt.partMessages(part: "p", index: 2, count: 3, hasSpeakers: false)[0].content.contains("parte 2 di 3"))
        XCTAssertTrue(SummaryPrompt.mergeMessages(partSummaries: ["A1", "B2"], hasSpeakers: false)[1].content.contains("B2"))
    }

    func testCleanReplyStripsFenceAndTitle() {
        XCTAssertEqual(SummaryPrompt.cleanReply("```markdown\n# Riassunto\n## Decisioni\n- A\n```\n"), "## Decisioni\n- A")
        XCTAssertEqual(SummaryPrompt.cleanReply("  ## Decisioni\n- A  "), "## Decisioni\n- A")
    }

    func testDocumentHeader() {
        let d = SummaryPrompt.document(title: "2026-11-18 10.02 Call", durationSeconds: 3480,
            date: Date(timeIntervalSince1970: 1_795_000_000), timeZone: TimeZone(identifier: "Europe/Rome")!, body: "## Decisioni\nNessuna")
        XCTAssertTrue(d.hasPrefix("# Riassunto — 2026-11-18 10.02 Call\nDurata: 58 min · Trascritto il "))
        XCTAssertTrue(d.hasSuffix("## Decisioni\nNessuna\n"))
        XCTAssertTrue(SummaryPrompt.document(title: "t", durationSeconds: 0, date: .now, timeZone: .current, body: "b").contains("Durata: 1 min"))
    }
}
