import AVFoundation
import CoreMedia
import CoreVideo
import NastroMedia

/// Synthetic media helpers for NastroMedia tests (no capture permission needed).
enum TestMedia {
    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// A solid-colour BGRA frame of the given size, presented at `at`.
    /// Duration is left invalid, like ScreenCaptureKit frames.
    static func videoFrame(width: Int, height: Int, at time: CMTime) -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32BGRA,
                                         attributes as CFDictionary, &pixelBuffer)
        precondition(status == kCVReturnSuccess, "CVPixelBufferCreate failed: \(status)")
        let buffer = pixelBuffer!

        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0..<height {
            let line = base + row * bytesPerRow
            for column in 0..<width {
                let pixel = line + column * 4
                pixel[0] = 0xC0 // B
                pixel[1] = 0x60 // G
                pixel[2] = 0x20 // R
                pixel[3] = 0xFF // A
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        var format: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &format)
        precondition(formatStatus == noErr, "format description failed: \(formatStatus)")

        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time,
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescription: format!,
            sampleTiming: &timing, sampleBufferOut: &sample)
        precondition(sampleStatus == noErr, "sample buffer failed: \(sampleStatus)")
        return sample!
    }

    /// PCM float (non-interleaved) 440 Hz sine at `amplitude` (0 = silence), starting at `at`,
    /// lasting `duration` (rounded to whole sample frames). Phase follows absolute time,
    /// so consecutive blocks join seamlessly.
    static func tone(sampleRate: Double, channels: Int, at time: CMTime,
                     duration: CMTime, amplitude: Double = 0.5) -> CMSampleBuffer {
        let frames = AVAudioFrameCount((duration.seconds * sampleRate).rounded())
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                   channels: AVAudioChannelCount(channels))!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        pcm.frameLength = frames
        let firstFrame = (time.seconds * sampleRate).rounded()
        for channel in 0..<channels {
            let data = pcm.floatChannelData![channel]
            for index in 0..<Int(frames) {
                let t = (firstFrame + Double(index)) / sampleRate
                data[index] = Float(amplitude * sin(2 * Double.pi * 440 * t))
            }
        }

        var sample: CMSampleBuffer?
        var status = CMAudioSampleBufferCreateWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
            makeDataReadyCallback: nil, refcon: nil,
            formatDescription: format.formatDescription,
            sampleCount: CMItemCount(frames), presentationTimeStamp: time,
            packetDescriptions: nil, sampleBufferOut: &sample)
        precondition(status == noErr, "audio sample buffer failed: \(status)")
        status = CMSampleBufferSetDataBufferFromAudioBufferList(
            sample!, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0,
            bufferList: pcm.audioBufferList)
        precondition(status == noErr, "audio data buffer failed: \(status)")
        return sample!
    }

    /// Number of video and audio tracks and the asset duration in seconds.
    static func tracks(of url: URL) async throws -> (video: Int, audio: Int, duration: Double) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.load(.tracks)
        let duration = try await asset.load(.duration)
        return (tracks.filter { $0.mediaType == .video }.count,
                tracks.filter { $0.mediaType == .audio }.count,
                duration.seconds)
    }

    /// An audio source for `makeWorkFile`: delivered for the whole duration, with the tone
    /// audible only inside `toneRange` (seconds) and silence elsewhere.
    struct WorkAudio {
        let kind: SampleKind
        let sampleRate: Double
        let channels: Int
        var toneRange: ClosedRange<Double>? = nil
    }

    /// Writes a real work file with `MovieWriter`: 640×360 frames at 30 fps (if `video`) and
    /// 1024-frame audio blocks, interleaved in presentation order, every source starting at
    /// the first timestamp so nothing waits for a missing format.
    static func makeWorkFile(at url: URL, video: Bool, audio: [WorkAudio],
                             duration: Double) async throws {
        let spec = VideoSpec(width: 640, height: 360, fps: 30)
        let writer = try MovieWriter(
            url: url, video: video ? spec : nil,
            systemAudio: audio.contains { $0.kind == .systemAudio },
            microphone: audio.contains { $0.kind == .microphone })
        let origin = 1000.0
        var events: [(time: CMTime, kind: SampleKind, buffer: () -> CMSampleBuffer)] = []
        if video {
            for offset in stride(from: 0.0, to: duration, by: 1.0 / 30) {
                let time = CMTime(seconds: origin + offset, preferredTimescale: 30_000)
                events.append((time, .video, {
                    videoFrame(width: spec.width, height: spec.height, at: time)
                }))
            }
        }
        for source in audio {
            let rate = CMTimeScale(source.sampleRate)
            var frame = Int64(origin * source.sampleRate)
            let end = Int64((origin + duration) * source.sampleRate)
            while frame < end {
                let time = CMTime(value: frame, timescale: rate)
                let offset = Double(frame) / source.sampleRate - origin
                let audible = source.toneRange.map { $0.contains(offset) } ?? true
                events.append((time, source.kind, {
                    tone(sampleRate: source.sampleRate, channels: source.channels, at: time,
                         duration: CMTime(value: 1024, timescale: rate),
                         amplitude: audible ? 0.5 : 0)
                }))
                frame += 1024
            }
        }
        events.sort { CMTimeCompare($0.time, $1.time) < 0 }
        for event in events {
            writer.append(event.kind, event.buffer())
        }
        guard case .written = try await writer.finish() else {
            throw Failure("work file not written")
        }
    }

    /// Codec of the first video track as a four-character string (e.g. "hvc1").
    static func videoCodec(of url: URL) async throws -> String {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first,
              let description = try await track.load(.formatDescriptions).first
        else { throw Failure("no video track") }
        let code = CMFormatDescriptionGetMediaSubType(description)
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Peak level (dBFS) of all audio tracks mixed, over `from…to` seconds.
    static func peakLevel(of url: URL, from start: Double, to end: Double) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw Failure("no audio track") }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 48_000),
            end: CMTime(seconds: end, preferredTimescale: 48_000))
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Failure("cannot read audio") }
        var peak: Float = 0
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = data.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                           destination: $0.baseAddress!)
            }
            guard status == noErr else { throw Failure("cannot copy audio: \(status)") }
            for value in data { peak = max(peak, abs(value)) }
        }
        guard reader.status == .completed else { throw reader.error ?? Failure("read failed") }
        return peak > 0 ? 20 * log10(Double(peak)) : -.infinity
    }

    /// Decodes the first audio track to interleaved float PCM and calls `visit` with each
    /// buffer's start time (seconds, file timeline), sample rate, channel count and samples.
    private static func readFirstAudioTrack(
        of url: URL, _ visit: (_ start: Double, _ rate: Double, _ channels: Int, _ samples: [Float]) -> Bool
    ) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first
        else { throw Failure("no audio track") }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Failure("cannot read audio") }
        defer { reader.cancelReading() }
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer),
                  let format = CMSampleBufferGetFormatDescription(buffer),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
            else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var data = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = data.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                           destination: $0.baseAddress!)
            }
            guard status == noErr else { throw Failure("cannot copy audio: \(status)") }
            let start = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            if !visit(start, asbd.mSampleRate, Int(asbd.mChannelsPerFrame), data) { return }
        }
    }

    /// Time (seconds, file timeline) of the first sample of the first audio track whose
    /// absolute value exceeds `threshold`; nil if none does.
    static func firstLoudTime(of url: URL, threshold: Float = 0.05) async throws -> Double? {
        var found: Double?
        try await readFirstAudioTrack(of: url) { start, rate, channels, samples in
            guard let index = samples.firstIndex(where: { abs($0) > threshold }) else { return true }
            found = start + Double(index / channels) / rate
            return false
        }
        return found
    }

    /// Peak level (dBFS) of each channel of the first audio track over `from…to` seconds.
    static func channelPeaks(of url: URL, from: Double, to: Double) async throws -> [Double] {
        var peaks: [Float] = []
        try await readFirstAudioTrack(of: url) { start, rate, channels, samples in
            if peaks.isEmpty { peaks = Array(repeating: 0, count: channels) }
            for (index, value) in samples.enumerated() {
                let time = start + Double(index / channels) / rate
                guard time >= from, time < to else { continue }
                peaks[index % channels] = max(peaks[index % channels], abs(value))
            }
            return true
        }
        return peaks.map { $0 > 0 ? 20 * log10(Double($0)) : -.infinity }
    }

    /// Sample rate and channel count of each audio track, in file order.
    static func audioFormats(of url: URL) async throws -> [(sampleRate: Double, channels: Int)] {
        let asset = AVURLAsset(url: url)
        var result: [(sampleRate: Double, channels: Int)] = []
        for track in try await asset.loadTracks(withMediaType: .audio) {
            for description in try await track.load(.formatDescriptions) {
                guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)
                else { throw Failure("audio track without stream description") }
                result.append((asbd.pointee.mSampleRate, Int(asbd.pointee.mChannelsPerFrame)))
            }
        }
        return result
    }
}
