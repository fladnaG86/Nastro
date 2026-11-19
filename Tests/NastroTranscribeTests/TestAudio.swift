import AVFoundation
import CoreMedia

/// Minimal synthetic audio writer for NastroTranscribe tests (pattern of NastroMediaTests' TestMedia;
/// test targets cannot share code).
enum TestAudio {
    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// PCM float (non-interleaved) 440 Hz sine at `amplitude` (0 = silence), starting at `at`.
    static func tone(sampleRate: Double, frames: Int, at time: CMTime, amplitude: Double) -> CMSampleBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        pcm.frameLength = AVAudioFrameCount(frames)
        let firstFrame = (time.seconds * sampleRate).rounded()
        let data = pcm.floatChannelData![0]
        for index in 0..<frames {
            let t = (firstFrame + Double(index)) / sampleRate
            data[index] = Float(amplitude * sin(2 * Double.pi * 440 * t))
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

    /// Writes an `.m4a` with one AAC 48 kHz mono track per entry of `amplitudes`
    /// (440 Hz tone at that amplitude, 0 = silence), each lasting `duration` seconds.
    static func makeFile(at url: URL, amplitudes: [Double], duration: Double) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ]
        let inputs = amplitudes.map { _ in
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            return input
        }
        guard writer.startWriting() else { throw writer.error ?? Failure("cannot start writing") }
        writer.startSession(atSourceTime: .zero)
        let rate = 48_000.0
        let total = Int(duration * rate)
        var frame = 0
        while frame < total {
            let count = min(1024, total - frame)
            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(rate))
            for (input, amplitude) in zip(inputs, amplitudes) {
                while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
                guard input.append(tone(sampleRate: rate, frames: count, at: time, amplitude: amplitude))
                else { throw writer.error ?? Failure("append failed") }
            }
            frame += count
        }
        inputs.forEach { $0.markAsFinished() }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? Failure("not written") }
    }
}
