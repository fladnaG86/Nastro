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

    public func transcribe(_ stream: AudioStream,
                           progress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment] {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [], attributeOptions: [.audioTimeRange])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let speaker = stream.speaker
        let duration = stream.duration
        let collector = Task {
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results {
                let start = result.range.start.seconds
                let end = CMTimeRangeGetEnd(result.range).seconds
                segments.append(TranscriptSegment(start: start, end: end,
                                                  text: String(result.text.characters), speaker: speaker))
                if duration > 0 { progress(min(max(end / duration, 0), 1)) }
            }
            return segments
        }
        do {
            let audioFile = try AVAudioFile(forReading: stream.file)
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
            throw Task.isCancelled ? SummaryError.cancelled : error
        }
    }
}
