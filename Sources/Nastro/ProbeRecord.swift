import AppKit
import CoreMedia
import Foundation
import NastroCore
import NastroMedia

/// Diagnostic: `Nastro --probe-record <seconds> <display|window|audio>` records for the given
/// seconds into `~/Movies/Nastro/` through CaptureSession → MovieWriter → Finalizer, prints one
/// line per stage and ends with `PROBE-RECORD ok <file>` (exit 0) or
/// `PROBE-RECORD failed <reason>` (exit 1).
enum ProbeRecord {
    private final class Sink: CaptureSink, @unchecked Sendable {
        let writer: MovieWriter
        private let lock = NSLock()
        private var counts: [SampleKind: Int] = [:]
        private var peaks: [SampleKind: Float] = [:]
        private var stopError: Error?
        private var stopped = false

        init(writer: MovieWriter) { self.writer = writer }

        func capture(_ kind: SampleKind, _ buffer: CMSampleBuffer) {
            let peak = kind == .video ? 0 : ProbeRecord.peak(buffer)
            lock.withLock {
                counts[kind, default: 0] += 1
                peaks[kind] = max(peaks[kind] ?? 0, peak)
            }
            writer.append(kind, buffer)
        }

        func captureStopped(error: Error?) {
            lock.withLock { stopped = true; stopError = error }
        }

        var summary: String {
            lock.withLock {
                func db(_ kind: SampleKind) -> String {
                    guard let p = peaks[kind], p > 0 else { return "-inf" }
                    return String(format: "%.1f", 20 * log10(Double(p)))
                }
                return "video=\(counts[.video] ?? 0) "
                    + "systemAudio=\(counts[.systemAudio] ?? 0) (peak \(db(.systemAudio)) dB) "
                    + "microphone=\(counts[.microphone] ?? 0) (peak \(db(.microphone)) dB)"
            }
        }

        var stoppedByItself: (Bool, Error?) { lock.withLock { (stopped, stopError) } }
    }

    private struct Failure: Error, CustomStringConvertible { let description: String }

    static func run(_ arguments: [String]) -> Never {
        guard arguments.count >= 2, let seconds = Double(arguments[0]), seconds > 0,
              ["display", "window", "audio"].contains(arguments[1]) else {
            print("usage: Nastro --probe-record <seconds> <display|window|audio>")
            exit(1)
        }
        // ScreenCaptureKit window filters need the window server connection NSApplication sets up.
        _ = NSApplication.shared
        Task {
            do {
                let path = try await record(seconds: seconds, source: arguments[1])
                print("PROBE-RECORD ok \(path)")
                exit(0)
            } catch {
                print("PROBE-RECORD failed \(error)")
                exit(1)
            }
        }
        dispatchMain()
    }

    private static func record(seconds: Double, source: String) async throws -> String {
        guard Permissions.screenGranted else { throw Failure(description: "PERMISSION: screen recording not granted") }
        print("permissions: screen granted, microphone authorized: \(Permissions.microphoneStatus == .authorized)")

        let sources = try await SourceCatalog.load()
        print("sources: displays \(sources.displays.map { "\($0.id) \"\($0.name)\"\($0.isMain ? " (main)" : "")" })")
        print("sources: \(sources.windows.count) windows: "
            + sources.windows.prefix(5).map { "\($0.id) \"\($0.title)\" (\($0.appName))" }.joined(separator: ", "))
        print("microphones: \(SourceCatalog.microphones().map(\.name))")

        var settings = Settings.default
        switch source {
        case "window":
            guard let window = sources.windows.first else { throw Failure(description: "no listable window on screen") }
            settings.videoSource = .window(id: window.id)
            print("source: window \(window.id) \"\(window.title)\" (\(window.appName))")
        case "audio":
            settings.mode = .audioOnly
            print("source: audio only")
        default:
            print("source: main display")
        }
        let hasVideo = settings.mode == .videoAndAudio

        try Destination.prepare(settings.outputFolder)
        let finalURL = FileNaming.finalURL(folder: settings.outputFolder, date: Date(), timeZone: .current,
                                           hasVideo: hasVideo,
                                           exists: { FileManager.default.fileExists(atPath: $0.path) })
        let workURL = FileNaming.workURL(forFinal: finalURL)

        // The session decides the video size; the writer needs it, and the sink needs the writer.
        let relay = Relay()
        let session = try CaptureSession(settings: settings, sources: sources, sink: relay)
        print("session: video \(session.videoSpec.map { "\($0.width)x\($0.height)@\($0.fps)" } ?? "none")")
        let writer = try MovieWriter(url: workURL, video: session.videoSpec,
                                     systemAudio: settings.systemAudio, microphone: settings.microphone)
        let sink = Sink(writer: writer)
        relay.target = sink

        try await session.start()
        print("capture: started, recording \(seconds) s")
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        await session.stop()
        print("capture: stopped, buffers \(sink.summary)")
        let (stopped, stopError) = sink.stoppedByItself
        if stopped { print("capture: a stream stopped by itself: \(stopError.map { "\($0)" } ?? "no error")") }

        let result = try await writer.finish()
        print("writer: \(result), without track \(writer.sourcesWithoutTrack), degraded \(writer.degradedSources)")
        guard case .written = result else { throw Failure(description: "nothing was written") }

        try await Finalizer.finalize(workFile: workURL, to: finalURL, keepSeparateTracks: settings.keepSeparateTracks)
        try FileManager.default.removeItem(at: workURL)
        print("finalizer: wrote \(finalURL.lastPathComponent)")
        return finalURL.path
    }

    /// Peak absolute amplitude of float32 PCM over all channels; 0 for other formats.
    static func peak(_ buffer: CMSampleBuffer) -> Float {
        guard let format = CMSampleBufferGetFormatDescription(buffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return 0 }
        var peak: Float = 0
        try? buffer.withAudioBufferList { list, _ in
            for audioBuffer in list {
                guard let data = audioBuffer.mData else { continue }
                let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self),
                                                  count: Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size)
                for sample in samples { peak = max(peak, abs(sample)) }
            }
        }
        return peak
    }

    /// Forwards to a sink set after the session exists (the writer needs the session's video size).
    private final class Relay: CaptureSink, @unchecked Sendable {
        private let lock = NSLock()
        private var _target: CaptureSink?
        var target: CaptureSink? {
            get { lock.withLock { _target } }
            set { lock.withLock { _target = newValue } }
        }

        func capture(_ kind: SampleKind, _ buffer: CMSampleBuffer) { target?.capture(kind, buffer) }
        func captureStopped(error: Error?) { target?.captureStopped(error: error) }
    }
}
