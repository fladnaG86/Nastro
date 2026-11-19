import AVFoundation
import Foundation
import NastroCore
import Speech

/// Turns one audio stream into timed transcript segments.
public protocol Transcriber: Sendable {
    func transcribe(_ stream: AudioStream, progress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment]
}

/// On-device transcription with the macOS 26 `SpeechAnalyzer` + `SpeechTranscriber`.
@available(macOS 26, *)
public struct SpeechTranscriberEngine: Transcriber {
    private let locale: Locale

    public init(locale: Locale = Locale(identifier: "it_IT")) {
        self.locale = locale
    }

    /// Makes sure the speech model for `locale` is on this Mac, downloading it if needed.
    /// Unsupported locale or a failed download throws `.speechModelUnavailable`.
    public static func prepareModel(locale: Locale = Locale(identifier: "it_IT")) async throws {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SummaryError.speechModelUnavailable
        }
        let installed = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
        if installed.contains(supported.identifier(.bcp47)) { return }
        let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [],
                                            reportingOptions: [], attributeOptions: [.audioTimeRange])
        do {
            try await AssetInventory.assetInstallationRequest(supporting: [transcriber])?.downloadAndInstall()
        } catch {
            throw SummaryError.speechModelUnavailable
        }
    }

    /// Throws only `SummaryError`: unreadable audio `.noAudio`, cancellation `.cancelled`,
    /// any other recognizer failure `.speechModelUnavailable`.
    public func transcribe(_ stream: AudioStream,
                           progress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment] {
        let audioFile: AVAudioFile
        do { audioFile = try AVAudioFile(forReading: stream.file) } catch { throw SummaryError.noAudio }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [], attributeOptions: [.audioTimeRange])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let speaker = stream.speaker
        let duration = stream.duration
        let collector = Task {
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results {
                // Non-finite times (invalid CMTime) would trap later in Int conversions.
                let finite: (Double) -> Double? = { $0.isFinite ? $0 : nil }
                let range = (start: finite(result.range.start.seconds) ?? 0,
                             end: finite(CMTimeRangeGetEnd(result.range).seconds) ?? 0)
                let words = result.text.runs.map { run in
                    SentenceSplitter.Word(text: String(result.text[run.range].characters),
                                          start: finite(run.audioTimeRange?.start.seconds ?? .nan),
                                          end: finite(run.audioTimeRange.map { CMTimeRangeGetEnd($0).seconds } ?? .nan))
                }
                segments += SentenceSplitter.split(words, range: range, speaker: speaker)
                if duration > 0 {
                    let fraction = range.end / duration
                    if fraction.isFinite { progress(min(max(fraction, 0), 1)) }
                }
            }
            return segments
        }
        do {
            if let last = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            try Task.checkCancellation()
            let segments = try await collector.value
            progress(1.0)
            return segments
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            if Task.isCancelled || error is CancellationError { throw SummaryError.cancelled }
            throw SummaryError.speechModelUnavailable
        }
    }
}
