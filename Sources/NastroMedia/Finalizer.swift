import AVFoundation
import CoreMedia
import NastroCore

public enum FinalizeError: Error, Equatable { case unreadable, noTracks, exportFailed }

/// Turns a work file into the final `.mp4` (video) or `.m4a` (audio only): video is copied
/// without re-encoding; two or more audio tracks are mixed into one AAC 48 kHz stereo track
/// unless `keepSeparateTracks`, in which case (as with a single audio track) every audio
/// track is copied as it is.
public enum Finalizer {
    static let mixedAudioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 160_000,
    ]

    /// PCM the mixer delivers to the AAC encoder (already at the output rate and layout).
    static let mixPCMSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsNonInterleaved: false,
        AVLinearPCMIsBigEndianKey: false,
    ]

    /// The file type (mp4 or m4a) follows the content: video → mp4, audio only → m4a,
    /// whatever the extension of `final`; the caller names the file with `hasVideo`.
    /// Never deletes `workFile`: the caller does that after success. The copy is written to
    /// `FileNaming.finalizingURL(forFinal: final)` and renamed to `final` only once complete;
    /// on failure (including `final` appearing meanwhile) the temporary file is deleted and
    /// nothing at `final` is touched.
    public static func finalize(workFile: URL, to final: URL, keepSeparateTracks: Bool) async throws {
        try await finalize(workFile: workFile, to: final, keepSeparateTracks: keepSeparateTracks,
                           failAppend: nil)
    }

    /// Test seam: consulted before each append with the input's media type and the number
    /// of samples already appended to it; `true` makes that append fail as if the writer
    /// had rejected it.
    typealias AppendFailure = @Sendable (_ mediaType: AVMediaType, _ appended: Int) -> Bool

    static func finalize(workFile: URL, to final: URL, keepSeparateTracks: Bool,
                         failAppend: AppendFailure?) async throws {
        let asset = AVURLAsset(url: workFile)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.load(.tracks)
        } catch {
            throw FinalizeError.unreadable
        }
        let videoTracks = tracks.filter { $0.mediaType == .video }
        let audioTracks = tracks.filter { $0.mediaType == .audio }
        guard !videoTracks.isEmpty || !audioTracks.isEmpty else { throw FinalizeError.noTracks }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw FinalizeError.unreadable
        }
        let fileManager = FileManager.default
        // Never overwrite (or, on failure, delete) a file that was already there.
        guard !fileManager.fileExists(atPath: final.path) else {
            throw FinalizeError.exportFailed
        }
        // The copy is written under a temporary sibling name, so an interrupted finalization
        // never leaves a partial file under the final name. A leftover temporary file is never
        // anyone's only copy (its work file still exists): it is replaced.
        let temporary = FileNaming.finalizingURL(forFinal: final)
        try? fileManager.removeItem(at: temporary)
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: temporary,
                                       fileType: videoTracks.isEmpty ? .m4a : .mp4)
        } catch {
            throw FinalizeError.exportFailed
        }

        do {
            let pairs = try await makePairs(reader: reader, writer: writer, video: videoTracks,
                                            audio: audioTracks,
                                            mix: audioTracks.count > 1 && !keepSeparateTracks)
            try await copy(pairs, reader: reader, writer: writer, failAppend: failAppend)
        } catch {
            if writer.status == .writing { writer.cancelWriting() }
            reader.cancelReading()
            try? fileManager.removeItem(at: temporary)
            throw error
        }
        // `moveItem` never replaces an existing file: a file that appeared at the final name
        // meanwhile is left alone.
        do {
            try fileManager.moveItem(at: temporary, to: final)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw FinalizeError.exportFailed
        }
    }

    public static func hasVideo(_ url: URL) async -> Bool {
        let tracks = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        return !(tracks ?? []).isEmpty
    }

    // MARK: - Private

    /// Not Sendable by nature (AVFoundation objects); see `CopySession` for the confinement.
    private struct Pair: @unchecked Sendable {
        let output: AVAssetReaderOutput
        let input: AVAssetWriterInput
    }

    private static func makePairs(reader: AVAssetReader, writer: AVAssetWriter,
                                  video: [AVAssetTrack], audio: [AVAssetTrack],
                                  mix: Bool) async throws -> [Pair] {
        var pairs: [Pair] = []

        func add(_ output: AVAssetReaderOutput, _ input: AVAssetWriterInput) throws {
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw FinalizeError.unreadable }
            guard writer.canAdd(input) else { throw FinalizeError.exportFailed }
            reader.add(output)
            writer.add(input)
            pairs.append(Pair(output: output, input: input))
        }

        func addCopy(of track: AVAssetTrack) async throws {
            let hint = try? await track.load(.formatDescriptions).first
            let input = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: nil,
                                           sourceFormatHint: hint)
            if track.mediaType == .video,
               let transform = try? await track.load(.preferredTransform) {
                input.transform = transform
            }
            try add(AVAssetReaderTrackOutput(track: track, outputSettings: nil), input)
        }

        for track in video { try await addCopy(of: track) }
        if mix {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audio,
                                                     audioSettings: mixPCMSettings)
            try add(output, AVAssetWriterInput(mediaType: .audio,
                                               outputSettings: mixedAudioSettings))
        } else {
            for track in audio { try await addCopy(of: track) }
        }
        return pairs
    }

    /// Pumps every output into its input (each on its own queue, so the writer can interleave)
    /// and closes the file.
    private static func copy(_ pairs: [Pair], reader: AVAssetReader, writer: AVAssetWriter,
                             failAppend: AppendFailure?) async throws {
        guard reader.startReading() else { throw FinalizeError.unreadable }
        guard writer.startWriting() else { throw FinalizeError.exportFailed }
        writer.startSession(atSourceTime: .zero)

        let session = CopySession(pairs: pairs, writer: writer, failAppend: failAppend)
        await session.run()

        if reader.status == .failed { throw FinalizeError.exportFailed }
        if session.appendFailed || writer.status != .writing {
            throw FinalizeError.exportFailed
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw FinalizeError.exportFailed }
    }

    /// Runs one pump per pair, each on its own serial queue (AVFoundation objects are not
    /// Sendable; a pair is only touched from its queue). Shared state is guarded by `lock`.
    ///
    /// `run()` always returns: a pump ends when its output is exhausted, and the first failure
    /// (a rejected append, or the writer leaving `.writing`, which a watchdog also polls for
    /// in case every input is waiting and no block runs again) ends every pump at once from
    /// the failure site. Each pump leaves the group exactly once, whichever happens first.
    private final class CopySession: @unchecked Sendable {
        private static let watchdogInterval = DispatchTimeInterval.milliseconds(250)

        private let pairs: [Pair]
        private let writer: AVAssetWriter
        private let failAppend: AppendFailure?
        private let group = DispatchGroup()
        private let queues: [DispatchQueue]
        private let lock = NSLock()
        private var failed = false
        private var ended: [Bool]
        private var appended: [Int]

        init(pairs: [Pair], writer: AVAssetWriter, failAppend: AppendFailure?) {
            self.pairs = pairs
            self.writer = writer
            self.failAppend = failAppend
            queues = pairs.indices.map { DispatchQueue(label: "Nastro.Finalizer.\($0)") }
            ended = Array(repeating: false, count: pairs.count)
            appended = Array(repeating: 0, count: pairs.count)
        }

        var appendFailed: Bool { lock.withLock { failed } }

        func run() async {
            let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            watchdog.schedule(deadline: .now() + Self.watchdogInterval,
                              repeating: Self.watchdogInterval)
            watchdog.setEventHandler { [self] in
                if writer.status != .writing { fail() }
            }

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                for index in pairs.indices {
                    group.enter()
                    pairs[index].input.requestMediaDataWhenReady(on: queues[index]) { [self] in
                        pump(index)
                    }
                }
                watchdog.resume()
                group.notify(queue: .global()) { [self] in
                    watchdog.cancel()
                    // Let any block still in the middle of an append return before the caller
                    // finishes or cancels the writer.
                    queues.forEach { $0.sync {} }
                    continuation.resume()
                }
            }
        }

        /// Body of the media-data block of pair `index` (runs on `queues[index]`).
        private func pump(_ index: Int) {
            let pair = pairs[index]
            while lock.withLock({ !ended[index] }) {
                guard writer.status == .writing else { return fail() }
                guard pair.input.isReadyForMoreMediaData else { return }
                guard let buffer = pair.output.copyNextSampleBuffer() else {
                    pair.input.markAsFinished()
                    return end([index])
                }
                guard append(buffer, to: index) else { return fail() }
            }
        }

        /// Appends through the test seam; counts successful appends per input.
        private func append(_ buffer: CMSampleBuffer, to index: Int) -> Bool {
            let input = pairs[index].input
            let count = lock.withLock { appended[index] }
            if failAppend?(input.mediaType, count) == true { return false }
            guard input.append(buffer) else { return false }
            lock.withLock { appended[index] += 1 }
            return true
        }

        /// Records the failure and ends every pump that has not ended yet.
        private func fail() {
            lock.withLock { failed = true }
            end(Array(pairs.indices))
        }

        /// Leaves the group once for each of `indices` that has not ended yet.
        private func end(_ indices: [Int]) {
            let leaving = lock.withLock {
                indices.filter { index in
                    defer { ended[index] = true }
                    return !ended[index]
                }
            }
            leaving.forEach { _ in group.leave() }
        }
    }
}
