import CoreMedia
import Foundation
import NastroCore
import NastroMedia

/// The capture sink. Runs on the capture threads: forwards every buffer to the writer at
/// once, measures audio peaks and feeds the silence detectors under a short lock, and hands
/// levels to the main actor at most 10 times per second without ever waiting for it.
final class RecordingSink: CaptureSink, @unchecked Sendable {
    struct Snapshot {
        let sawVideo: Bool
        let systemSilent: Bool
        let microphoneSilent: Bool
        let lastSampleAt: [SampleKind: TimeInterval]

        func secondsSinceSample(_ kind: SampleKind, now: TimeInterval) -> TimeInterval {
            lastSampleAt[kind].map { now - $0 } ?? .infinity
        }
    }

    static let levelInterval: TimeInterval = 0.1

    static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    private let onLevels: @Sendable (Float?, Float?) -> Void
    private let onStopped: @Sendable (Error?) -> Void
    private let lock = NSLock()
    private var writer: MovieWriter?
    private var systemDetector = SilenceDetector()
    private var microphoneDetector = SilenceDetector()
    private var sawVideo = false
    private var lastSampleAt: [SampleKind: TimeInterval] = [:]
    private var pendingPeak: [SampleKind: Float] = [:]
    private var lastPublishAt: TimeInterval = 0

    /// `onLevels(system, microphone)`: the loudest peak (dBFS) since the previous call, `nil`
    /// for a source with no samples in between. Both callbacks run on a capture thread.
    init(onLevels: @escaping @Sendable (Float?, Float?) -> Void, onStopped: @escaping @Sendable (Error?) -> Void) {
        self.onLevels = onLevels
        self.onStopped = onStopped
    }

    func attach(_ writer: MovieWriter) { lock.withLock { self.writer = writer } }

    /// Starts the silence grace periods.
    func begin(at t: TimeInterval) {
        lock.withLock {
            systemDetector.start(at: t)
            microphoneDetector.start(at: t)
        }
    }

    func snapshot(at t: TimeInterval) -> Snapshot {
        lock.withLock {
            Snapshot(sawVideo: sawVideo, systemSilent: systemDetector.isSilent(at: t),
                     microphoneSilent: microphoneDetector.isSilent(at: t), lastSampleAt: lastSampleAt)
        }
    }

    func capture(_ kind: SampleKind, _ buffer: CMSampleBuffer) {
        lock.withLock { writer }?.append(kind, buffer)
        let t = Self.now()
        guard kind != .video else {
            lock.withLock { sawVideo = true }
            return
        }
        let level = Self.peakDB(buffer)
        let publish: (Float?, Float?)? = lock.withLock {
            lastSampleAt[kind] = t
            if let level {
                if kind == .systemAudio {
                    systemDetector.feed(levelDB: level, at: t)
                } else {
                    microphoneDetector.feed(levelDB: level, at: t)
                }
                pendingPeak[kind] = max(pendingPeak[kind] ?? AudioLevel.floorDB, level)
            }
            guard t - lastPublishAt >= Self.levelInterval, !pendingPeak.isEmpty else { return nil }
            defer { pendingPeak = [:]; lastPublishAt = t }
            return (pendingPeak[.systemAudio], pendingPeak[.microphone])
        }
        if let publish { onLevels(publish.0, publish.1) }
    }

    func captureStopped(error: Error?) { onStopped(error) }

    /// Peak of float32 PCM over all channels; `nil` for other formats.
    static func peakDB(_ buffer: CMSampleBuffer) -> Float? {
        guard let format = CMSampleBufferGetFormatDescription(buffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0, asbd.mBitsPerChannel == 32 else { return nil }
        var peak = AudioLevel.floorDB
        try? buffer.withAudioBufferList { list, _ in
            for audioBuffer in list {
                guard let data = audioBuffer.mData else { continue }
                let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self),
                                                  count: Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size)
                peak = max(peak, AudioLevel.peakDB(samples))
            }
        }
        return peak
    }
}
