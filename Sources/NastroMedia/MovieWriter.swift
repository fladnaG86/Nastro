import AVFoundation
import CoreMedia

/// Outcome of `MovieWriter.finish()`.
public enum WriteResult: Equatable, Sendable {
    case written(duration: Double)
    case empty
}

/// Writes live screen video, system audio and microphone samples into a crash-tolerant
/// fragmented QuickTime work file (HEVC video, one AAC track per audio source).
///
/// Audio inputs are created from the first sample of each source (its native format), but
/// `AVAssetWriter` accepts no new inputs after `startWriting`, so writing waits until every
/// expected source has shown its format or 2 s of presentation time have passed since the
/// first accepted sample. Sources still silent at that point get no track. During the wait
/// audio is queued but only the newest video frame is held (capture frames come from a small
/// pool); in video mode the session starts at that frame, so a missing source delays the
/// start by up to 2 s.
public final class MovieWriter: @unchecked Sendable {
    /// Presentation-time wait for audio sources to show their format.
    static let formatWait = CMTime(value: 2, timescale: 1)

    private enum Phase { case collecting, writing, failed, finishing, done }

    private let url: URL
    private let video: VideoSpec?
    private let expectedAudio: [SampleKind]
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput?

    private let lock = NSLock()
    private var phase = Phase.collecting
    private var audioFormats: [SampleKind: CMAudioFormatDescription] = [:]
    private var audioInputs: [SampleKind: AVAssetWriterInput] = [:]
    /// Audio queued during the format wait.
    private var pending: [(kind: SampleKind, buffer: CMSampleBuffer)] = []
    /// Newest frame seen during the format wait (video mode).
    private var heldFrame: CMSampleBuffer?
    /// Time of the first accepted sample: the format wait is measured from here.
    private var waitStart: CMTime?
    private var sessionStart: CMTime?
    private var lastVideoFrame: CMSampleBuffer?
    private var lastVideoTime = CMTime.invalid
    private var lastAudioTime = CMTime.invalid
    private var endTime = CMTime.invalid
    private var firstError: Error?

    /// `video == nil` → audio only. Creates the file at `url` (.mov).
    public init(url: URL, video: VideoSpec?, systemAudio: Bool, microphone: Bool) throws {
        self.url = url
        self.video = video
        var expected: [SampleKind] = []
        if systemAudio { expected.append(.systemAudio) }
        if microphone { expected.append(.microphone) }
        self.expectedAudio = expected

        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.movieFragmentInterval = CMTime(value: 10, timescale: 1)
        writer.initialMovieFragmentInterval = CMTime(value: 2, timescale: 1)

        if let video {
            let bitRate = Double(video.width * video.height * video.fps) * 0.05
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: video.width,
                AVVideoHeightKey: video.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: Int(bitRate),
                ],
            ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                throw AVError(.encoderNotFound)
            }
            writer.add(input)
            videoInput = input
        } else {
            videoInput = nil
        }
    }

    /// First write error, if any.
    public var failure: Error? {
        lock.lock()
        defer { lock.unlock() }
        return firstError
    }

    /// Callable from any thread; serialised internally. Never blocks waiting for the encoder:
    /// a sample the input is not ready for is dropped.
    public func append(_ kind: SampleKind, _ buffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        switch phase {
        case .collecting:
            collect(kind, buffer)
        case .writing:
            write(kind, buffer)
        case .failed, .finishing, .done:
            break
        }
    }

    /// Closes the file. Returns `.empty` (and deletes the file) if no sample was ever accepted.
    /// If writing failed, throws `failure` and leaves the work file on disk (it is fragmented,
    /// so what was written before the failure may still be recoverable).
    public func finish() async throws -> WriteResult {
        enum Step { case close(start: CMTime), discard, fail(Error) }
        let step: Step = lock.withLock {
            if phase == .collecting, waitStart != nil {
                startWriting()
            }
            switch phase {
            case .writing:
                break
            case .failed:
                phase = .done
                return .fail(firstError ?? AVError(.unknown))
            case .collecting, .finishing, .done:
                phase = .done
                return .discard
            }
            phase = .finishing
            extendStaticScreen()
            if phase == .failed {
                phase = .done
                return .fail(firstError ?? AVError(.unknown))
            }
            guard endTime.isValid, let start = sessionStart else {
                // Writing started but every sample was dropped: nothing to keep.
                writer.cancelWriting()
                phase = .done
                return .discard
            }
            videoInput?.markAsFinished()
            audioInputs.values.forEach { $0.markAsFinished() }
            writer.endSession(atSourceTime: endTime)
            return .close(start: start)
        }

        let start: CMTime
        switch step {
        case .fail(let error):
            throw error
        case .discard:
            try? FileManager.default.removeItem(at: url)
            return .empty
        case .close(let value):
            start = value
        }

        await writer.finishWriting()
        return try lock.withLock {
            phase = .done
            if writer.status != .completed {
                if firstError == nil { firstError = writer.error ?? AVError(.unknown) }
            }
            if let firstError { throw firstError }
            return .written(duration: (endTime - start).seconds)
        }
    }

    // MARK: - Collecting (before startWriting)

    private func collect(_ kind: SampleKind, _ buffer: CMSampleBuffer) {
        let time = CMSampleBufferGetPresentationTimeStamp(buffer)
        if kind == .video {
            guard video != nil else { return }
            // Only the newest frame is held: capture frames come from a small pool.
            heldFrame = buffer
            if waitStart == nil { waitStart = time }
        } else {
            guard expectedAudio.contains(kind) else { return }
            // Formats are noted only while collecting: a source first seen after the wait
            // never gets an input. Audio before the first frame still reveals its format.
            if audioFormats[kind] == nil, let format = CMSampleBufferGetFormatDescription(buffer) {
                audioFormats[kind] = format
            }
            if video == nil {
                if waitStart == nil { waitStart = time }
            } else if waitStart == nil {
                return // video mode: audio before the first frame is discarded
            }
            pending.append((kind, buffer))
        }

        guard let waitStart else { return }
        let allShown = expectedAudio.allSatisfy { audioFormats[$0] != nil }
        if allShown || time - waitStart >= Self.formatWait {
            startWriting()
        }
    }

    /// Adds an input per audio source seen so far, starts the session (at the held frame in
    /// video mode, at the first audio sample otherwise) and flushes what was held.
    private func startWriting() {
        let frame = heldFrame
        heldFrame = nil
        if video != nil {
            guard let frame else { return }
            sessionStart = CMSampleBufferGetPresentationTimeStamp(frame)
        } else {
            guard let first = pending.first else { return }
            sessionStart = CMSampleBufferGetPresentationTimeStamp(first.buffer)
        }
        guard let sessionStart else { return }
        for kind in expectedAudio {
            guard let format = audioFormats[kind],
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
            else { continue }
            let channels = Int(asbd.mChannelsPerFrame)
            var settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: asbd.mSampleRate,
                AVNumberOfChannelsKey: channels,
            ]
            if let bitRate = Self.aacBitRate(sampleRate: asbd.mSampleRate, channels: channels) {
                settings[AVEncoderBitRateKey] = bitRate
            }
            if channels > 2 {
                var layout = AudioChannelLayout()
                layout.mChannelLayoutTag = kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)
                settings[AVChannelLayoutKey] = Data(bytes: &layout,
                                                    count: MemoryLayout<AudioChannelLayout>.size)
            }
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings,
                                           sourceFormatHint: format)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                record(AVError(.encoderNotFound))
                return
            }
            writer.add(input)
            audioInputs[kind] = input
        }

        guard writer.startWriting() else {
            record(writer.error ?? AVError(.unknown))
            return
        }
        writer.startSession(atSourceTime: sessionStart)
        phase = .writing

        if let frame { write(.video, frame) }
        let queued = pending
        pending = []
        // Audio earlier than the session start is dropped by `write`.
        for sample in queued where phase == .writing {
            write(sample.kind, sample.buffer)
        }
    }

    // MARK: - Writing

    private func write(_ kind: SampleKind, _ buffer: CMSampleBuffer) {
        guard let sessionStart else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(buffer)
        guard time >= sessionStart else { return }
        let input: AVAssetWriterInput?
        switch kind {
        case .video:
            input = videoInput
            // Frames must advance; a repeated timestamp would fail the whole writer.
            if lastVideoTime.isValid, time <= lastVideoTime { return }
        case .systemAudio, .microphone:
            input = audioInputs[kind]
        }
        guard let input, input.isReadyForMoreMediaData else { return }

        guard input.append(buffer) else {
            record(writer.error ?? AVError(.unknown))
            return
        }
        let duration = CMSampleBufferGetDuration(buffer)
        let end = duration.isNumeric ? time + duration : time
        if !endTime.isValid || end > endTime { endTime = end }
        if kind == .video {
            lastVideoFrame = buffer
            lastVideoTime = time
        } else if !lastAudioTime.isValid || time > lastAudioTime {
            lastAudioTime = time
        }
    }

    /// Static screen: if the last frame is older than the last audio sample, writes it again
    /// at the audio time so the video lasts as long as the audio.
    private func extendStaticScreen() {
        guard let frame = lastVideoFrame, lastAudioTime.isValid, lastAudioTime > lastVideoTime
        else { return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: lastAudioTime,
                                        decodeTimeStamp: .invalid)
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: frame, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleBufferOut: &copy)
        guard status == noErr, let copy else { return }
        write(.video, copy)
    }

    /// AAC target (128 kb/s for two channels, 64 kb/s for one) capped at the encoder's maximum
    /// for this rate and channel count (e.g. 48 kb/s at 16 kHz mono, 24 kb/s at 8 kHz mono).
    /// `nil` when the encoder cannot be queried: the encoder then picks the bitrate.
    static func aacBitRate(sampleRate: Double, channels: Int) -> Int? {
        let target = channels >= 2 ? 128_000 : 64_000
        var source = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channels), mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(4 * channels), mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32, mReserved: 0)
        var destination = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0,
            mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 0, mReserved: 0)
        var converter: AudioConverterRef?
        guard AudioConverterNew(&source, &destination, &converter) == noErr,
              let converter else { return nil }
        defer { AudioConverterDispose(converter) }

        var size: UInt32 = 0
        guard AudioConverterGetPropertyInfo(converter, kAudioConverterApplicableEncodeBitRates,
                                            &size, nil) == noErr,
              size >= UInt32(MemoryLayout<AudioValueRange>.size) else { return nil }
        var ranges = [AudioValueRange](repeating: AudioValueRange(),
                                       count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioConverterGetProperty(converter, kAudioConverterApplicableEncodeBitRates,
                                        &size, &ranges) == noErr,
              let maximum = ranges.map({ Int($0.mMaximum) }).max(), maximum > 0
        else { return nil }
        return min(target, maximum)
    }

    private func record(_ error: Error) {
        if firstError == nil { firstError = error }
        pending = []
        heldFrame = nil
        phase = .failed
    }
}
