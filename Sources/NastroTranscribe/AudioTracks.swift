import AVFoundation
import Foundation
import NastroCore

/// One audio track of a recording, decoded to a 16 kHz mono Float32 `.caf` file.
public struct AudioStream: Sendable {
    public var file: URL
    public var speaker: Speaker?
    public var duration: TimeInterval

    public init(file: URL, speaker: Speaker?, duration: TimeInterval) {
        self.file = file
        self.speaker = speaker
        self.duration = duration
    }
}

public enum AudioTracks {
    static let sampleRate = 16_000.0

    /// Decodes every audio track of `recording` (at most two) into `dir` as `track-<n>.caf`.
    /// One track has no speaker; two tracks are system audio then microphone (`MovieWriter`
    /// order), so `[.others, .me]`. No audio track or an unreadable file throws `.noAudio`.
    public static func extract(from recording: URL, into dir: URL) async throws -> [AudioStream] {
        let asset = AVURLAsset(url: recording)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw SummaryError.noAudio
        }
        guard !tracks.isEmpty else { throw SummaryError.noAudio }
        let used = Array(tracks.prefix(2))
        let speakers: [Speaker?] = used.count == 1 ? [nil] : [.others, .me]
        var streams: [AudioStream] = []
        for (index, track) in used.enumerated() {
            let file = dir.appendingPathComponent("track-\(index + 1).caf")
            let frames = try decode(track, of: asset, to: file)
            streams.append(AudioStream(file: file, speaker: speakers[index], duration: Double(frames) / sampleRate))
        }
        return streams
    }

    /// Reads `track` resampled to 16 kHz mono Float32 and writes it to `file`; returns the frame count.
    private static func decode(_ track: AVAssetTrack, of asset: AVAsset, to file: URL) throws -> Int64 {
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw SummaryError.noAudio }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        guard reader.canAdd(output) else { throw SummaryError.noAudio }
        reader.add(output)
        guard reader.startReading() else { throw SummaryError.noAudio }
        defer { reader.cancelReading() }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                   channels: 1, interleaved: false)!
        try? FileManager.default.removeItem(at: file)
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forWriting: file, settings: format.settings,
                                        commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw SummaryError.cannotWrite
        }
        var frames: Int64 = 0
        while let sample = output.copyNextSampleBuffer() {
            if Task.isCancelled { throw SummaryError.cancelled }
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let count = length / MemoryLayout<Float>.size
            guard count > 0,
                  let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))
            else { continue }
            let status = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                                                    destination: pcm.floatChannelData![0])
            guard status == noErr else { throw SummaryError.noAudio }
            pcm.frameLength = AVAudioFrameCount(count)
            do { try audioFile.write(from: pcm) } catch { throw SummaryError.cannotWrite }
            frames += Int64(count)
        }
        guard reader.status == .completed else { throw SummaryError.noAudio }
        return frames
    }
}
