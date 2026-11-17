import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import NastroCore
import NastroMedia
import ScreenCaptureKit

protocol CaptureSink: AnyObject, Sendable {
    /// Called on a capture thread.
    func capture(_ kind: SampleKind, _ buffer: CMSampleBuffer)
    /// A stream stopped by itself (not through `CaptureSession.stop()`).
    func captureStopped(error: Error?)
}

enum CaptureError: Error { case sourceUnavailable, noPermission }

/// Turns the settings into running ScreenCaptureKit stream(s) and forwards their samples to a
/// sink. With a window source, or in audio-only mode, audio travels on a placeholder stream on
/// the main display (see `CapturePlanner`).
final class CaptureSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private struct Prepared {
        let plan: StreamPlan
        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
    }

    let videoSpec: VideoSpec?

    private let sink: CaptureSink
    private let prepared: [Prepared]
    private let wantsMicrophone: Bool
    private let lock = NSLock()
    private var streams: [SCStream] = []
    /// Set by `stop()` or by the first stream that stops by itself; afterwards nothing more
    /// is forwarded and the sink is not notified again.
    private var finished = false

    /// Resolves `settings.videoSource` in `sources`; if the saved window or display no longer
    /// exists throws `.sourceUnavailable` (a saved display falls back to the main one).
    init(settings: Settings, sources: Sources, sink: CaptureSink) throws {
        let content = sources.content
        let mainID = CGMainDisplayID()
        guard let target = CaptureTargets.resolve(
            settings.mode == .audioOnly ? .mainDisplay : settings.videoSource,
            displayIDs: content.displays.map(\.displayID), mainDisplayID: mainID,
            windowIDs: content.windows.map(\.windowID))
        else { throw CaptureError.sourceUnavailable }

        let plans = CapturePlanner.streams(mode: settings.mode, target: target, mainDisplayID: mainID,
                                           systemAudio: settings.systemAudio, microphone: settings.microphone)
        let excluded = content.applications.filter { SourceCatalog.isNastro($0) }
        let fps = max(settings.fps, 1)
        var prepared: [Prepared] = []
        var spec: VideoSpec?
        for plan in plans {
            let filter: SCContentFilter
            let pointSize: CGSize
            switch plan.target {
            case .display(let id):
                guard let display = content.displays.first(where: { $0.displayID == id }) else {
                    throw CaptureError.sourceUnavailable
                }
                filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
                pointSize = CGSize(width: display.width, height: display.height)
            case .window(let id):
                guard let window = content.windows.first(where: { $0.windowID == id }) else {
                    throw CaptureError.sourceUnavailable
                }
                filter = SCContentFilter(desktopIndependentWindow: window)
                pointSize = window.frame.size
            }

            let configuration = SCStreamConfiguration()
            configuration.capturesAudio = plan.systemAudio
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = true
            configuration.captureMicrophone = plan.microphone
            configuration.microphoneCaptureDeviceID = settings.microphoneID
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.showsCursor = true
            configuration.queueDepth = 6
            switch plan.video {
            case .full:
                let points = filter.contentRect.isEmpty ? pointSize : filter.contentRect.size
                let scale = CGFloat(filter.pointPixelScale)
                let size = VideoSizing.outputSize(sourceWidth: Int((points.width * scale).rounded()),
                                                  sourceHeight: Int((points.height * scale).rounded()),
                                                  maxLongSide: settings.maxLongSide)
                configuration.width = size.width
                configuration.height = size.height
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
                spec = VideoSpec(width: size.width, height: size.height, fps: fps)
            case .placeholder:
                configuration.width = 2
                configuration.height = 2
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            }
            prepared.append(Prepared(plan: plan, filter: filter, configuration: configuration))
        }
        self.prepared = prepared
        self.videoSpec = spec
        self.sink = sink
        self.wantsMicrophone = settings.microphone
        super.init()
    }

    /// Starts the streams in plan order (the audio-carrying one first). If one fails to
    /// start, every stream created so far is stopped and the error is thrown. If the session
    /// is stopped while starting (by `stop()` or by a stream stopping itself), every stream
    /// created so far is stopped and `CancellationError` is thrown: the session is not running.
    func start() async throws {
        guard Permissions.screenGranted else { throw CaptureError.noPermission }
        if wantsMicrophone, [.denied, .restricted].contains(Permissions.microphoneStatus) {
            throw CaptureError.noPermission
        }
        // Every stream this call creates, so a failed or cancelled start can stop them all even
        // if a concurrent `stop()` already took them from `streams`.
        var created: [SCStream] = []
        do {
            for (index, item) in prepared.enumerated() {
                let stream = SCStream(filter: item.filter, configuration: item.configuration, delegate: self)
                created.append(stream)
                let queue = DispatchQueue(label: "it.nastro.capture.\(index)", qos: .userInteractive)
                if item.plan.video == .full {
                    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
                }
                if item.plan.systemAudio {
                    try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
                }
                if item.plan.microphone {
                    try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
                }
                let registered: Bool = lock.withLock {
                    guard !finished else { return false }
                    streams.append(stream)
                    return true
                }
                guard registered else { throw CancellationError() }
                try await stream.startCapture()
                if lock.withLock({ finished }) { throw CancellationError() }
            }
        } catch {
            lock.withLock {
                finished = true
                streams = []
            }
            await tearDown(created)
            if let scError = error as? SCStreamError, scError.code == .userDeclined {
                throw CaptureError.noPermission
            }
            throw error
        }
    }

    /// Stops every stream; the sink is not notified.
    func stop() async {
        let toStop: [SCStream] = lock.withLock {
            finished = true
            defer { streams = [] }
            return streams
        }
        await tearDown(toStop)
    }

    /// Stops the streams and detaches the session from them (harmless on a stream that is
    /// already stopped or never started).
    private func tearDown(_ toStop: [SCStream]) async {
        for stream in toStop {
            try? await stream.stopCapture()
            for type in [SCStreamOutputType.screen, .audio, .microphone] {
                try? stream.removeStreamOutput(self, type: type)
            }
        }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard buffer.isValid, !lock.withLock({ finished }) else { return }
        switch type {
        case .screen:
            if Self.isComplete(buffer) { sink.capture(.video, buffer) }
        case .audio:
            sink.capture(.systemAudio, buffer)
        case .microphone:
            sink.capture(.microphone, buffer)
        @unknown default:
            break
        }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let all: [SCStream]? = lock.withLock {
            guard !finished else { return nil }
            finished = true
            defer { streams = [] }
            return streams
        }
        guard let all else { return }
        sink.captureStopped(error: error)
        // Includes the stream that stopped: stopping it again is harmless and detaches the session.
        Task { await self.tearDown(all) }
    }

    private static func isComplete(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete
    }
}
