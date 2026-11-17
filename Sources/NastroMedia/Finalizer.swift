import AVFoundation
import CoreMedia

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
    /// Never deletes `workFile`: the caller does that after success. On failure, whatever
    /// was written at `final` is deleted.
    public static func finalize(workFile: URL, to final: URL, keepSeparateTracks: Bool) async throws {
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
        // Never overwrite (or, on failure, delete) a file that was already there.
        guard !FileManager.default.fileExists(atPath: final.path) else {
            throw FinalizeError.exportFailed
        }
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: final,
                                       fileType: videoTracks.isEmpty ? .m4a : .mp4)
        } catch {
            throw FinalizeError.exportFailed
        }

        do {
            let pairs = try await makePairs(reader: reader, writer: writer, video: videoTracks,
                                            audio: audioTracks,
                                            mix: audioTracks.count > 1 && !keepSeparateTracks)
            try await copy(pairs, reader: reader, writer: writer)
        } catch {
            if writer.status == .writing { writer.cancelWriting() }
            reader.cancelReading()
            try? FileManager.default.removeItem(at: final)
            throw error
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
    private static func copy(_ pairs: [Pair], reader: AVAssetReader,
                             writer: AVAssetWriter) async throws {
        guard reader.startReading() else { throw FinalizeError.unreadable }
        guard writer.startWriting() else { throw FinalizeError.exportFailed }
        writer.startSession(atSourceTime: .zero)

        let session = CopySession(pairs: pairs, writer: writer)
        await session.run()

        if reader.status == .failed { throw FinalizeError.exportFailed }
        if session.appendFailed || writer.status != .writing {
            throw FinalizeError.exportFailed
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw FinalizeError.exportFailed }
    }

    /// AVFoundation objects are not Sendable; each pair is touched only from its own serial
    /// queue, and `appendFailed` is guarded by `lock`.
    private final class CopySession: @unchecked Sendable {
        private let pairs: [Pair]
        private let writer: AVAssetWriter
        private let lock = NSLock()
        private var failed = false

        init(pairs: [Pair], writer: AVAssetWriter) {
            self.pairs = pairs
            self.writer = writer
        }

        var appendFailed: Bool { lock.withLock { failed } }

        func run() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let group = DispatchGroup()
                for (index, pair) in pairs.enumerated() {
                    group.enter()
                    let queue = DispatchQueue(label: "Nastro.Finalizer.\(index)")
                    pair.input.requestMediaDataWhenReady(on: queue) { [self] in
                        while pair.input.isReadyForMoreMediaData {
                            var done = appendFailed || writer.status != .writing
                            if !done {
                                if let buffer = pair.output.copyNextSampleBuffer() {
                                    if !pair.input.append(buffer) {
                                        lock.withLock { failed = true }
                                        done = true
                                    }
                                } else {
                                    done = true
                                }
                            }
                            if done {
                                pair.input.markAsFinished()
                                group.leave()
                                return
                            }
                        }
                    }
                }
                group.notify(queue: .global()) { continuation.resume() }
            }
        }
    }
}
