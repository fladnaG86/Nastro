import XCTest
import NastroCore
@testable import NastroTranscribe

/// Thread-safe box for state the fakes and callbacks record.
private final class Recorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.lock(); defer { lock.unlock() }; return value }
    func mutate(_ change: (inout Value) -> Void) { lock.lock(); change(&value); lock.unlock() }
}

/// Canned segments per speaker; counts calls; optional delay before answering.
private struct FakeTranscriber: Transcriber {
    var segments: [Speaker?: [TranscriptSegment]]
    var delay: Duration? = nil
    let calls = Recorder(0)

    func transcribe(_ stream: AudioStream, progress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment] {
        calls.mutate { $0 += 1 }
        if let delay { try await Task.sleep(for: delay) }
        progress(0.5)
        progress(1.0)
        return segments[stream.speaker] ?? []
    }
}

/// Canned replies in order (or a thrown error); records the messages of every call.
private struct FakeChat: ChatClient {
    var replies: [String] = []
    var error: SummaryError? = nil
    let sent = Recorder<[[ChatMessage]]>([])

    func complete(_ messages: [ChatMessage]) async throws -> String {
        let index = sent.get().count
        sent.mutate { $0.append(messages) }
        if let error { throw error }
        return replies[min(index, replies.count - 1)]
    }
}

final class SummaryPipelineTests: XCTestCase {
    private var folder: URL!
    private var recording: URL!
    private let fixedDate = Date(timeIntervalSince1970: 1_795_000_000)

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SummaryPipelineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        recording = folder.appendingPathComponent("2026-11-18 10.02 Call.mp4")
        try Data("not a movie".utf8).write(to: recording)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: folder)
    }

    private var transcriptURL: URL { SiblingFiles.transcriptURL(for: recording) }
    private var summaryURL: URL { SiblingFiles.summaryURL(for: recording) }

    private func folderContents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    private func tempFiles() throws -> [String] {
        try folderContents().filter { $0.hasSuffix(SiblingFiles.tempSuffix) }
    }

    private static let twoSpeakers: [Speaker?: [TranscriptSegment]] = [
        .others: [TranscriptSegment(start: 0, end: 2, text: "Ciao, mi senti?", speaker: .others),
                  TranscriptSegment(start: 10, end: 12, text: "Allora ci vediamo giovedì.", speaker: .others)],
        .me: [TranscriptSegment(start: 4, end: 6, text: "Sì, ti sento bene.", speaker: .me)],
    ]

    private func twoStreams(_ dir: URL) -> [AudioStream] {
        [AudioStream(file: dir.appendingPathComponent("track-1.caf"), speaker: .others, duration: 12),
         AudioStream(file: dir.appendingPathComponent("track-2.caf"), speaker: .me, duration: 12)]
    }

    private func makePipeline(transcriber: FakeTranscriber, chat: FakeChat,
                              prepareCalls: Recorder<Int> = Recorder(0)) -> SummaryPipeline {
        SummaryPipeline(
            transcriber: transcriber, chat: chat,
            prepare: { prepareCalls.mutate { $0 += 1 } },
            extract: { [self] _, dir in twoStreams(dir) },
            duration: { _ in 125 },
            now: { [fixedDate] in fixedDate })
    }

    private func run(_ pipeline: SummaryPipeline, phases: Recorder<[SummaryPhase]> = Recorder([])) async throws -> SummaryResult {
        try await pipeline.run(recording: recording, phase: { phase in phases.mutate { $0.append(phase) } })
    }

    private func assertThrows(_ expected: SummaryError, _ body: () async throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("expected \(expected), nothing thrown", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? SummaryError, expected, file: file, line: line)
        }
    }

    func testWritesTranscriptAndSummary() async throws {
        let transcriber = FakeTranscriber(segments: Self.twoSpeakers)
        let chat = FakeChat(replies: ["## Di cosa si è parlato\nSaluti.\n\n## Decisioni\nNessuna\n\n## Cose da fare\nNessuna"])
        let phases = Recorder<[SummaryPhase]>([])
        let result = try await run(makePipeline(transcriber: transcriber, chat: chat), phases: phases)

        XCTAssertEqual(result, SummaryResult(transcript: transcriptURL, summary: summaryURL, failure: nil))
        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)
        XCTAssertEqual(transcript, """
            [00:00:00] Altri: Ciao, mi senti?
            [00:00:04] Io: Sì, ti sento bene.
            [00:00:10] Altri: Allora ci vediamo giovedì.

            """)
        let summary = try String(contentsOf: summaryURL, encoding: .utf8)
        XCTAssertTrue(summary.hasPrefix("# Riassunto — 2026-11-18 10.02 Call\nDurata: 2 min · Trascritto il "), summary)
        XCTAssertTrue(summary.contains("## Di cosa si è parlato\nSaluti."))
        XCTAssertEqual(try tempFiles(), [])
        XCTAssertEqual(transcriber.calls.get(), 2)
        XCTAssertEqual(chat.sent.get(), [SummaryPrompt.summaryMessages(transcript: transcript, hasSpeakers: true)])
        let recorded = phases.get()
        XCTAssertEqual(recorded.first, .preparing)
        XCTAssertTrue(recorded.contains(.transcribing(0.25)), "\(recorded)")
        XCTAssertTrue(recorded.contains(.transcribing(1.0)), "\(recorded)")
        XCTAssertEqual(recorded.last, .summarizing(part: 1, of: 1))
    }

    func testReusesExistingTranscript() async throws {
        let existing = "[00:00:01] Io: Testo già trascritto.\n"
        try existing.write(to: transcriptURL, atomically: true, encoding: .utf8)
        let transcriber = FakeTranscriber(segments: Self.twoSpeakers)
        let chat = FakeChat(replies: ["Riassunto"])
        let prepareCalls = Recorder(0)
        let extractCalls = Recorder(0)
        let pipeline = SummaryPipeline(
            transcriber: transcriber, chat: chat,
            prepare: { prepareCalls.mutate { $0 += 1 } },
            extract: { _, _ in extractCalls.mutate { $0 += 1 }; return [] },
            duration: { _ in 60 }, now: { [fixedDate] in fixedDate })
        let phases = Recorder<[SummaryPhase]>([])
        let result = try await run(pipeline, phases: phases)

        XCTAssertEqual(result.summary, summaryURL)
        XCTAssertEqual(transcriber.calls.get(), 0)
        XCTAssertEqual(prepareCalls.get(), 0)
        XCTAssertEqual(extractCalls.get(), 0)
        XCTAssertEqual(phases.get(), [.summarizing(part: 1, of: 1)])
        XCTAssertEqual(try String(contentsOf: transcriptURL, encoding: .utf8), existing)
        XCTAssertEqual(chat.sent.get(), [SummaryPrompt.summaryMessages(transcript: existing, hasSpeakers: true)])
    }

    func testBlankExistingTranscriptIsRedone() async throws {
        try " \n\t\n".write(to: transcriptURL, atomically: true, encoding: .utf8)
        let transcriber = FakeTranscriber(segments: Self.twoSpeakers)
        let prepareCalls = Recorder(0)
        _ = try await run(makePipeline(transcriber: transcriber, chat: FakeChat(replies: ["R"]), prepareCalls: prepareCalls))

        XCTAssertEqual(prepareCalls.get(), 1)
        XCTAssertEqual(transcriber.calls.get(), 2)
        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)
        XCTAssertTrue(transcript.hasPrefix("[00:00:00] Altri: Ciao, mi senti?\n"), transcript)
        XCTAssertEqual(try tempFiles(), [])
    }

    func testOneSilentTrackStillWrites() async throws {
        let transcriber = FakeTranscriber(segments: [
            .others: [],
            .me: [TranscriptSegment(start: 3, end: 5, text: "Parlo solo io.", speaker: .me)],
        ])
        let result = try await run(makePipeline(transcriber: transcriber, chat: FakeChat(replies: ["R"])))

        XCTAssertNil(result.failure)
        XCTAssertEqual(try String(contentsOf: transcriptURL, encoding: .utf8), "[00:00:03] Io: Parlo solo io.\n")
    }

    func testAllSilentThrowsNoSpeech() async throws {
        let transcriber = FakeTranscriber(segments: [:])
        let chat = FakeChat(replies: ["R"])
        await assertThrows(.noSpeech) { _ = try await self.run(self.makePipeline(transcriber: transcriber, chat: chat)) }

        XCTAssertEqual(try folderContents(), ["2026-11-18 10.02 Call.mp4"])
        XCTAssertEqual(chat.sent.get().count, 0)
    }

    func testChatUnreachableKeepsTranscript() async throws {
        let chat = FakeChat(error: .modelUnreachable(url: "http://127.0.0.1:8001/v1"))
        let result = try await run(makePipeline(transcriber: FakeTranscriber(segments: Self.twoSpeakers), chat: chat))

        XCTAssertEqual(result, SummaryResult(transcript: transcriptURL, summary: nil,
                                             failure: .modelUnreachable(url: "http://127.0.0.1:8001/v1")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: transcriptURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: summaryURL.path))
        XCTAssertEqual(try tempFiles(), [])
    }

    func testExistingSummaryIsReplaced() async throws {
        try "# Vecchio riassunto\n".write(to: summaryURL, atomically: true, encoding: .utf8)
        let result = try await run(makePipeline(transcriber: FakeTranscriber(segments: Self.twoSpeakers),
                                                chat: FakeChat(replies: ["Nuovo contenuto"])))

        XCTAssertEqual(result.summary, summaryURL)
        let summary = try String(contentsOf: summaryURL, encoding: .utf8)
        XCTAssertTrue(summary.contains("Nuovo contenuto"))
        XCTAssertFalse(summary.contains("Vecchio"))
        XCTAssertEqual(try tempFiles(), [])
    }

    func testLongTranscriptSummarizesPartsThenMerges() async throws {
        let line = "[00:00:01] Io: " + String(repeating: "parola ", count: 10) + "\n"
        let transcript = String(repeating: line, count: SummaryPrompt.singlePassMaxChars / line.count + 50)
        try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)
        let parts = SummaryPrompt.chunks(transcript)
        XCTAssertGreaterThan(parts.count, 1)
        let replies = (1...parts.count).map { "Appunti \($0)" } + ["Riassunto finale"]
        let chat = FakeChat(replies: replies)
        let phases = Recorder<[SummaryPhase]>([])
        let result = try await run(makePipeline(transcriber: FakeTranscriber(segments: [:]), chat: chat), phases: phases)

        let sent = chat.sent.get()
        XCTAssertEqual(sent.count, parts.count + 1)
        for (i, part) in parts.enumerated() {
            XCTAssertEqual(sent[i], SummaryPrompt.partMessages(part: part, index: i + 1, count: parts.count, hasSpeakers: true))
        }
        XCTAssertEqual(sent.last, SummaryPrompt.mergeMessages(partSummaries: Array(replies.dropLast()), hasSpeakers: true))
        XCTAssertEqual(phases.get(), (1...parts.count + 1).map { .summarizing(part: $0, of: parts.count + 1) })
        let summary = try String(contentsOf: XCTUnwrap(result.summary), encoding: .utf8)
        XCTAssertTrue(summary.hasSuffix("\n\nRiassunto finale\n"), summary)
    }

    func testCancelRemovesTemps() async throws {
        let transcriber = FakeTranscriber(segments: Self.twoSpeakers, delay: .seconds(30))
        let pipeline = makePipeline(transcriber: transcriber, chat: FakeChat(replies: ["R"]))
        let task = Task { try await run(pipeline) }
        while transcriber.calls.get() == 0 { try await Task.sleep(for: .milliseconds(10)) }
        task.cancel()
        await assertThrows(.cancelled) { _ = try await task.value }

        XCTAssertEqual(try folderContents(), ["2026-11-18 10.02 Call.mp4"])
    }

    func testUnwritableFolderThrowsCannotWrite() async throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        let chat = FakeChat(replies: ["R"])
        await assertThrows(.cannotWrite) {
            _ = try await self.run(self.makePipeline(transcriber: FakeTranscriber(segments: Self.twoSpeakers), chat: chat))
        }

        XCTAssertEqual(try folderContents(), ["2026-11-18 10.02 Call.mp4"])
        XCTAssertEqual(chat.sent.get().count, 0)
    }
}
