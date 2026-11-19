import AVFoundation
import Speech
import XCTest
import NastroCore
@testable import NastroTranscribe

/// Integration test: real SpeechAnalyzer on speech synthesized by `say`.
final class SpeechTranscriberEngineTests: XCTestCase {
    /// Collects progress values from a `@Sendable` callback.
    private final class ProgressLog: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Double] = []
        func append(_ value: Double) { lock.lock(); stored.append(value); lock.unlock() }
        var values: [Double] { lock.lock(); defer { lock.unlock() }; return stored }
    }

    /// Name of the first installed `it_IT` voice in `say -v '?'` (text before the locale column).
    private func italianVoice() throws -> String? {
        let output = try run("/usr/bin/say", ["-v", "?"])
        for line in output.split(separator: "\n") {
            guard let range = line.range(of: " it_IT") else { continue }
            let name = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        return nil
    }

    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw TestAudio.Failure("\(tool) exited \(process.terminationStatus)") }
        return String(decoding: data, as: UTF8.self)
    }

    func testTranscribesItalianSpeech() async throws {
        guard #available(macOS 26, *) else { throw XCTSkip("SpeechAnalyzer requires macOS 26") }
        guard SpeechTranscriber.isAvailable else { throw XCTSkip("SpeechTranscriber not available") }
        guard let voice = try italianVoice() else { throw XCTSkip("no it_IT voice for say") }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SpeechEngineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let speech = dir.appendingPathComponent("speech.aiff")
        try run("/usr/bin/say", ["-v", voice, "-o", speech.path, "Buongiorno a tutti, oggi parliamo del preventivo."])
        let audio = try AVAudioFile(forReading: speech)
        let duration = Double(audio.length) / audio.fileFormat.sampleRate

        try await SpeechTranscriberEngine.prepareModel()
        let log = ProgressLog()
        let segments = try await SpeechTranscriberEngine().transcribe(
            AudioStream(file: speech, speaker: .me, duration: duration),
            progress: { log.append($0) })

        XCTAssertFalse(segments.isEmpty)
        let text = segments.map(\.text).joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("preventivo"), "transcript: \(text)")
        for segment in segments {
            XCTAssertLessThan(segment.start, segment.end)
            XCTAssertEqual(segment.speaker, .me)
        }
        XCTAssertEqual(log.values.last, 1.0)
    }
}
