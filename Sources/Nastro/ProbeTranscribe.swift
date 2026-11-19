import Foundation
import NastroCore
import NastroTranscribe

/// `Nastro --probe-transcribe <file>` transcribes a recording from the terminal: prepares the
/// Italian speech model, extracts the audio tracks, transcribes each one, merges them and writes
/// `<base>.trascrizione.txt` next to the file (temp file + rename). Prints the stream count,
/// the elapsed seconds and the output path; any failure prints the error and exits 1.
enum ProbeTranscribe {
    static func run(_ arguments: [String]) -> Never {
        guard let path = arguments.first else {
            print("usage: Nastro --probe-transcribe <file>")
            exit(1)
        }
        guard #available(macOS 26, *) else {
            print("PROBE-TRANSCRIBE failed requires macOS 26")
            exit(1)
        }
        let recording = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        Task {
            do {
                try await transcribe(recording)
                exit(0)
            } catch {
                print("PROBE-TRANSCRIBE failed \(error)")
                exit(1)
            }
        }
        dispatchMain()
    }

    @available(macOS 26, *)
    private static func transcribe(_ recording: URL) async throws {
        let started = Date()
        try await SpeechTranscriberEngine.prepareModel()
        print("model ready after \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nastro-probe-transcribe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let streams = try await AudioTracks.extract(from: recording, into: dir)
        let audioSeconds = streams.map(\.duration).max() ?? 0
        print("streams: \(streams.count), audio \(String(format: "%.1f", audioSeconds)) s")
        let engine = SpeechTranscriberEngine()
        var results: [[TranscriptSegment]] = []
        for stream in streams {
            results.append(try await engine.transcribe(stream, progress: { _ in }))
        }
        let text = Transcript.render(Transcript.merge(results))

        let final = SiblingFiles.transcriptURL(for: recording)
        let temp = SiblingFiles.tempURL(for: final)
        do {
            try Data(text.utf8).write(to: temp)
            if FileManager.default.fileExists(atPath: final.path) {
                try FileManager.default.removeItem(at: final)
            }
            try FileManager.default.moveItem(at: temp, to: final)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw SummaryError.cannotWrite
        }
        let elapsed = Date().timeIntervalSince(started)
        print("PROBE-TRANSCRIBE ok \(streams.count) streams, \(String(format: "%.1f", elapsed)) s elapsed, "
            + "\(String(format: "%.1f", audioSeconds)) s audio -> \(final.path)")
    }
}
