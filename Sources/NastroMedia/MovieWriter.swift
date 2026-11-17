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
///
/// While writing, audio is never dropped because its input is momentarily not ready: each
/// source has a FIFO (bounded to `audioBacklogLimit` of audio; beyond it the oldest buffer
/// is dropped and counted in `droppedAudioBuffers`) drained in order on that source's later
/// appends and at `finish()`. `AVAssetWriter` joins audio buffers end to end, so a gap in a
/// source's timestamps longer than one buffer is filled with silence in that source's format
/// to keep the voice in sync with the video.
public final class MovieWriter: @unchecked Sendable {
    /// Presentation-time wait for audio sources to show their format.
    static let formatWait = CMTime(value: 2, timescale: 1)
    /// Audio kept per source while its input is not ready.
    static let audioBacklogLimit = CMTime(value: 10, timescale: 1)
    /// Longest silence appended at once when filling a gap.
    static let silenceChunk = CMTime(value: 1, timescale: 1)
    /// How long `finish()` waits for the inputs to accept the queued audio and the tail frame.
    static let finishWait: TimeInterval = 2

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
    private var finishTask: Task<WriteResult, Error>?
    private var sessionStarted = false
    private var degraded: Set<SampleKind> = []
    /// Presentation time of the last buffer accepted (queued or appended) per audio source.
    private var lastAcceptedAudio: [SampleKind: CMTime] = [:]
    /// Audio accepted but not yet appended, oldest first, per source.
    private var backlog: [SampleKind: [CMSampleBuffer]] = [:]
    private var backlogDuration: [SampleKind: CMTime] = [:]
    /// Where the audio appended so far ends, per source (for gap filling).
    private var audioEnd: [SampleKind: CMTime] = [:]
    private var dropped: [SampleKind: Int] = [:]
    private var _readinessOverride: (@Sendable (SampleKind) -> Bool)?

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

    /// Audio sources enabled in `init` that got no track because they had not shown their
    /// format when writing started. Empty until the session starts. Readable from any thread.
    public var sourcesWithoutTrack: Set<SampleKind> {
        lock.withLock {
            guard sessionStarted else { return [] }
            return Set(expectedAudio).subtracting(audioInputs.keys)
        }
    }

    /// Test seam: when set and returning false, the input of that kind counts as not ready
    /// (it can never make a busy input ready). Called with the writer's lock held.
    var readinessOverride: (@Sendable (SampleKind) -> Bool)? {
        get { lock.withLock { _readinessOverride } }
        set { lock.withLock { _readinessOverride = newValue } }
    }

    /// Audio buffers really lost per source (only sources with at least one): dropped because
    /// the source's queue exceeded `audioBacklogLimit`, or still queued when `finish()` gave
    /// up waiting. Readable from any thread.
    public var droppedAudioBuffers: [SampleKind: Int] {
        lock.withLock { dropped }
    }

    /// Audio sources whose format changed after their track was created. Their track ends at
    /// the change and all their later buffers are dropped. Readable from any thread.
    public var degradedSources: Set<SampleKind> {
        lock.withLock { degraded }
    }

    /// Callable from any thread; serialised internally. Never blocks waiting for the encoder:
    /// a video frame the input is not ready for is dropped, audio waits in its source's queue.
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
    /// Calling it again returns the first call's outcome (waiting for it if still running).
    public func finish() async throws -> WriteResult {
        let task: Task<WriteResult, Error> = lock.withLock {
            if let finishTask { return finishTask }
            let task = Task { try await self.closeFile() }
            finishTask = task
            return task
        }
        return try await task.value
    }

    /// The one-time body of `finish()`. Runs off the capture threads: the waits for the
    /// inputs happen here, never in `append`.
    private func closeFile() async throws -> WriteResult {
        enum Step { case close(start: CMTime), discard, fail(Error) }
        // 1. Stop accepting samples.
        let early: Step? = lock.withLock {
            if phase == .collecting, waitStart != nil {
                startWriting()
            }
            switch phase {
            case .writing:
                phase = .finishing
                return nil
            case .failed:
                phase = .done
                return .fail(firstError ?? AVError(.unknown))
            case .collecting:
                // Nothing was ever accepted: the file was never started.
                phase = .done
                return .discard
            case .finishing, .done:
                // Unreachable: this body runs once. Never touch the file here.
                return .fail(firstError ?? AVError(.unknown))
            }
        }

        if early == nil {
            // 2. Queued audio, in order, as the inputs accept it.
            await waitForInputs {
                expectedAudio.forEach(drain)
                return backlog.values.allSatisfy(\.isEmpty)
            }
            // 3. Static screen: the last frame again at the last audio time.
            let tail: CMSampleBuffer? = lock.withLock {
                for (kind, queue) in backlog where !queue.isEmpty {
                    dropped[kind, default: 0] += queue.count   // the input never took them
                }
                backlog = [:]
                return staticScreenTailFrame()
            }
            if let tail {
                await waitForInputs { isReady(.video) }
                lock.withLock {
                    if phase == .finishing { write(.video, tail) }
                }
            }
        }

        // 4. Close.
        let step: Step = early ?? lock.withLock {
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
        sessionStarted = true
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

    /// Video: appended if its input is ready, otherwise dropped. Audio: checked, queued in its
    /// source's FIFO, and the FIFO drained as far as the input accepts.
    private func write(_ kind: SampleKind, _ buffer: CMSampleBuffer) {
        guard let sessionStart else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(buffer)
        guard time >= sessionStart else { return }
        switch kind {
        case .video:
            // Frames must advance; a repeated timestamp would fail the whole writer.
            if lastVideoTime.isValid, time <= lastVideoTime { return }
            guard let videoInput, isReady(.video) else { return }
            append(.video, buffer, to: videoInput)
        case .systemAudio, .microphone:
            guard audioInputs[kind] != nil, !degraded.contains(kind) else { return }
            // A format change (e.g. the mic device switched rate) ends this source's track
            // instead of risking a failed append that would stop the whole recording.
            guard let trackFormat = audioFormats[kind],
                  let format = CMSampleBufferGetFormatDescription(buffer),
                  CMAudioFormatDescriptionEqual(
                      trackFormat, otherFormatDescription: format,
                      equalityMask: kCMAudioFormatDescriptionMask_StreamBasicDescription,
                      equalityMaskOut: nil)
            else {
                degraded.insert(kind)
                return
            }
            // Audio must advance per source; a stray backwards buffer is just dropped.
            if let last = lastAcceptedAudio[kind], time <= last { return }
            lastAcceptedAudio[kind] = time
            enqueue(kind, buffer)
            drain(kind)
        }
    }

    private func isReady(_ kind: SampleKind) -> Bool {
        guard let input = kind == .video ? videoInput : audioInputs[kind] else { return false }
        return (_readinessOverride?(kind) ?? true) && input.isReadyForMoreMediaData
    }

    /// Adds `buffer` to its source's FIFO; beyond `audioBacklogLimit` the oldest buffers are
    /// dropped and counted.
    private func enqueue(_ kind: SampleKind, _ buffer: CMSampleBuffer) {
        backlog[kind, default: []].append(buffer)
        var total = (backlogDuration[kind] ?? .zero) + Self.duration(of: buffer)
        while total > Self.audioBacklogLimit, let queue = backlog[kind], queue.count > 1 {
            total = total - Self.duration(of: queue[0])
            backlog[kind]?.removeFirst()
            dropped[kind, default: 0] += 1
        }
        backlogDuration[kind] = total
    }

    /// Appends the source's queued audio in order while its input is ready. Before a buffer
    /// that starts more than one buffer's duration after the audio written so far ends, the
    /// gap is filled with silence (in chunks of at most `silenceChunk`): `AVAssetWriter` would
    /// otherwise join the two and move the rest of that voice earlier.
    private func drain(_ kind: SampleKind) {
        guard let input = audioInputs[kind] else { return }
        while phase == .writing || phase == .finishing, let head = backlog[kind]?.first, isReady(kind) {
            let start = CMSampleBufferGetPresentationTimeStamp(head)
            let duration = Self.duration(of: head)
            if let end = audioEnd[kind], start - end > duration,
               let silence = makeSilence(kind, at: end, duration: min(start - end, Self.silenceChunk)) {
                guard append(kind, silence, to: input) else { return }
                continue
            }
            backlog[kind]?.removeFirst()
            backlogDuration[kind] = (backlogDuration[kind] ?? .zero) - duration
            guard append(kind, head, to: input) else { return }
        }
    }

    /// Appends to the input (already checked ready). False (and the writer failed) if rejected.
    @discardableResult
    private func append(_ kind: SampleKind, _ buffer: CMSampleBuffer, to input: AVAssetWriterInput) -> Bool {
        guard input.append(buffer) else {
            record(writer.error ?? AVError(.unknown))
            return false
        }
        let time = CMSampleBufferGetPresentationTimeStamp(buffer)
        if kind == .video {
            let duration = CMSampleBufferGetDuration(buffer)
            let end = duration.isNumeric ? time + duration : time
            if !endTime.isValid || end > endTime { endTime = end }
            lastVideoFrame = buffer
            lastVideoTime = time
        } else {
            let end = time + Self.duration(of: buffer)
            if !endTime.isValid || end > endTime { endTime = end }
            audioEnd[kind] = end
            if !lastAudioTime.isValid || time > lastAudioTime { lastAudioTime = time }
        }
        return true
    }

    /// An audio buffer's duration, from its sample count when it carries none.
    private static func duration(of buffer: CMSampleBuffer) -> CMTime {
        let duration = CMSampleBufferGetDuration(buffer)
        if duration.isNumeric { return duration }
        guard let format = CMSampleBufferGetFormatDescription(buffer),
              let rate = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee.mSampleRate,
              rate > 0
        else { return .zero }
        return CMTime(value: CMTimeValue(CMSampleBufferGetNumSamples(buffer)), timescale: CMTimeScale(rate))
    }

    /// Silence in the source's own (linear PCM, float or signed integer) format, starting at
    /// `time`; nil for any other format.
    private func makeSilence(_ kind: SampleKind, at time: CMTime, duration: CMTime) -> CMSampleBuffer? {
        guard let format = audioFormats[kind],
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM,
              asbd.mFormatFlags & (kAudioFormatFlagIsFloat | kAudioFormatFlagIsSignedInteger) != 0,
              asbd.mBytesPerFrame > 0, asbd.mSampleRate > 0
        else { return nil }
        let frames = Int((duration.seconds * asbd.mSampleRate).rounded())
        guard frames > 0 else { return nil }
        // Non-interleaved data is one plane per channel, one after the other.
        let planes = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? Int(asbd.mChannelsPerFrame) : 1
        let bytes = frames * Int(asbd.mBytesPerFrame) * planes
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
                blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag,
                blockBufferOut: &block) == kCMBlockBufferNoErr,
              let block,
              CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0,
                                         dataLength: bytes) == kCMBlockBufferNoErr
        else { return nil }
        var sample: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                sampleCount: frames, presentationTimeStamp: time, packetDescriptions: nil,
                sampleBufferOut: &sample) == noErr
        else { return nil }
        return sample
    }

    /// Static screen: if the last frame is older than the last audio sample, a copy of it at
    /// the audio time, so the video lasts as long as the audio; nil otherwise.
    private func staticScreenTailFrame() -> CMSampleBuffer? {
        guard let frame = lastVideoFrame, lastAudioTime.isValid, lastAudioTime > lastVideoTime
        else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: lastAudioTime,
                                        decodeTimeStamp: .invalid)
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: frame, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleBufferOut: &copy)
        guard status == noErr, let copy else { return nil }
        return copy
    }

    /// Calls `condition` under the lock until it holds, writing stops (failure), or
    /// `finishWait` has passed, sleeping briefly between attempts. Only used by `finish()`.
    private func waitForInputs(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(Self.finishWait)
        while true {
            let done = lock.withLock { phase != .finishing || condition() }
            if done || Date() >= deadline { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
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
        backlog = [:]
        backlogDuration = [:]
        phase = .failed
    }
}
