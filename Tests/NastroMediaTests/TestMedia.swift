import AVFoundation
import CoreMedia
import CoreVideo

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

    /// PCM float (non-interleaved) 440 Hz sine at amplitude 0.5, starting at `at`,
    /// lasting `duration` (rounded to whole sample frames). Phase follows absolute time,
    /// so consecutive blocks join seamlessly.
    static func tone(sampleRate: Double, channels: Int, at time: CMTime,
                     duration: CMTime) -> CMSampleBuffer {
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
                data[index] = Float(0.5 * sin(2 * Double.pi * 440 * t))
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
