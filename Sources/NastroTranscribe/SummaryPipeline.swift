import AVFoundation
import Foundation
import NastroCore

/// Outcome of a pipeline run. `summary == nil && failure != nil` means the transcript was
/// saved but the summary could not be made.
public struct SummaryResult: Sendable, Equatable {
    public var transcript: URL
    public var summary: URL?
    public var failure: SummaryError?

    public init(transcript: URL, summary: URL?, failure: SummaryError?) {
        self.transcript = transcript
        self.summary = summary
        self.failure = failure
    }
}

/// Recording -> `<base>.trascrizione.txt` -> `<base>.riassunto.md`. A non-blank transcript
/// already on disk is reused. Files are written to `<final>.nastro-tmp` and renamed.
/// Throws only `SummaryError`; a chat or summary-write failure is returned in the result.
public struct SummaryPipeline: Sendable {
    private let transcriber: any Transcriber
    private let chat: any ChatClient
    private let prepare: @Sendable () async throws -> Void
    private let extract: @Sendable (URL, URL) async throws -> [AudioStream]
    private let duration: @Sendable (URL) async -> TimeInterval
    private let now: @Sendable () -> Date

    public init(transcriber: any Transcriber,
                chat: any ChatClient,
                prepare: @escaping @Sendable () async throws -> Void,
                extract: @escaping @Sendable (URL, URL) async throws -> [AudioStream] = { try await AudioTracks.extract(from: $0, into: $1) },
                duration: @escaping @Sendable (URL) async -> TimeInterval = { await SummaryPipeline.assetDuration($0) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.transcriber = transcriber
        self.chat = chat
        self.prepare = prepare
        self.extract = extract
        self.duration = duration
        self.now = now
    }

    /// Duration of the recording in seconds; 0 when unreadable.
    public static func assetDuration(_ url: URL) async -> TimeInterval {
        guard let seconds = try? await AVURLAsset(url: url).load(.duration).seconds, seconds.isFinite else { return 0 }
        return seconds
    }

    public func run(recording: URL, phase: @escaping @Sendable (SummaryPhase) -> Void) async throws -> SummaryResult {
        do {
            let transcriptURL = SiblingFiles.transcriptURL(for: recording)
            let transcript = try await loadOrTranscribe(recording, to: transcriptURL, phase: phase)
            let summary = try await summarize(transcript, recording: recording, phase: phase)
            switch summary {
            case .success(let url): return SummaryResult(transcript: transcriptURL, summary: url, failure: nil)
            case .failure(let error): return SummaryResult(transcript: transcriptURL, summary: nil, failure: error)
            }
        } catch is CancellationError {
            throw SummaryError.cancelled
        }
    }

    // MARK: - Transcript

    private func loadOrTranscribe(_ recording: URL, to final: URL,
                                  phase: @escaping @Sendable (SummaryPhase) -> Void) async throws -> String {
        if let existing = try? String(contentsOf: final, encoding: .utf8), !Transcript.isBlank(existing) {
            return existing
        }
        phase(.preparing)
        do { try await prepare() } catch { throw Self.map(error, otherwise: .speechModelUnavailable) }
        try Task.checkCancellation()

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nastro-summary-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw SummaryError.cannotWrite
        }
        defer { try? FileManager.default.removeItem(at: dir) }

        let streams: [AudioStream]
        do { streams = try await extract(recording, dir) } catch { throw Self.map(error, otherwise: .noAudio) }

        var results: [[TranscriptSegment]] = []
        let count = Double(max(streams.count, 1))
        for (index, stream) in streams.enumerated() {
            try Task.checkCancellation()
            let done = Double(index)
            do {
                results.append(try await transcriber.transcribe(stream, progress: { fraction in
                    phase(.transcribing((done + min(max(fraction, 0), 1)) / count))
                }))
            } catch {
                throw Self.map(error, otherwise: .speechModelUnavailable)
            }
            phase(.transcribing((done + 1) / count))
        }
        try Task.checkCancellation()

        let segments = Transcript.merge(results)
        guard !segments.isEmpty else { throw SummaryError.noSpeech }
        let text = Transcript.render(segments)
        try Self.write(text, to: final)
        return text
    }

    // MARK: - Summary

    private func summarize(_ transcript: String, recording: URL,
                           phase: @escaping @Sendable (SummaryPhase) -> Void) async throws -> Result<URL, SummaryError> {
        let hasSpeakers = Transcript.hasSpeakers(transcript)
        let parts = SummaryPrompt.chunks(transcript)
        let reply: String
        do {
            if parts.count == 1 {
                phase(.summarizing(part: 1, of: 1))
                reply = try await complete(SummaryPrompt.summaryMessages(transcript: transcript, hasSpeakers: hasSpeakers))
            } else {
                let total = parts.count + 1
                var notes: [String] = []
                for (index, part) in parts.enumerated() {
                    phase(.summarizing(part: index + 1, of: total))
                    let note = try await complete(SummaryPrompt.partMessages(
                        part: part, index: index + 1, count: parts.count, hasSpeakers: hasSpeakers))
                    notes.append(SummaryPrompt.cleanReply(note))
                }
                phase(.summarizing(part: total, of: total))
                reply = try await complete(SummaryPrompt.mergeMessages(partSummaries: notes, hasSpeakers: hasSpeakers))
            }
        } catch let error as SummaryError {
            return .failure(error)
        }

        let document = SummaryPrompt.document(
            title: recording.deletingPathExtension().lastPathComponent,
            durationSeconds: Int(await duration(recording)),
            date: now(), timeZone: .current,
            body: SummaryPrompt.cleanReply(reply))
        try Task.checkCancellation()
        let final = SiblingFiles.summaryURL(for: recording)
        do {
            try Self.write(document, to: final)
        } catch let error as SummaryError {
            return .failure(error)
        }
        return .success(final)
    }

    /// One chat call. Cancellation propagates; any non-`SummaryError` failure (outside the
    /// `ChatClient` contract) becomes `.http(status: 0, detail:)` with its description.
    private func complete(_ messages: [ChatMessage]) async throws -> String {
        do {
            let reply = try await chat.complete(messages)
            try Task.checkCancellation()
            return reply
        } catch SummaryError.cancelled {
            throw CancellationError()
        } catch let error as SummaryError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SummaryError.http(status: 0, detail: String(describing: error))
        }
    }

    // MARK: - Helpers

    /// `SummaryError` passes through, cancellation becomes `CancellationError`, anything else `otherwise`.
    private static func map(_ error: Error, otherwise: SummaryError) -> Error {
        if error is CancellationError || (error as? SummaryError) == .cancelled { return CancellationError() }
        if let error = error as? SummaryError { return error }
        return otherwise
    }

    /// Writes `text` to `<final>.nastro-tmp`, then renames it over `final` (atomic replace when
    /// it exists). Any failure removes the temp file and throws `.cannotWrite`.
    private static func write(_ text: String, to final: URL) throws {
        let temp = SiblingFiles.tempURL(for: final)
        let fm = FileManager.default
        do {
            try Data(text.utf8).write(to: temp)
            if fm.fileExists(atPath: final.path) {
                _ = try fm.replaceItemAt(final, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: final)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw SummaryError.cannotWrite
        }
    }
}
