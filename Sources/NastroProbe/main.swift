import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import NastroMedia
import ScreenCaptureKit

// NastroProbe: measures how the capture APIs really behave on this machine.
// Subcommands: window-audio | audio-only | mic-format | crash-write <file> | inspect <file> | windows <owner>
// Every capture subcommand ends with a line `RESULT <letter> yes|no <measure>`.

func fail(_ message: String, code: Int32 = 1) -> Never {
    print(message)
    exit(code)
}

func requireScreenAccess() {
    guard CGPreflightScreenCaptureAccess() else {
        fail("PERMISSION: screen recording not granted", code: 2)
    }
}

func requireMicrophoneAccess() {
    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
        fail("PERMISSION: microphone not granted", code: 2)
    }
}

// MARK: - Capture collector

/// Receives stream output and keeps counters; thread-safe.
final class Collector: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var audioCount = 0
    private(set) var micCount = 0
    private(set) var screenCount = 0
    private(set) var audioPeak: Float = 0
    private(set) var micPeak: Float = 0
    private(set) var firstAudioTime: CMTime?
    private(set) var firstMicTime: CMTime?
    private(set) var micFormat: AudioStreamBasicDescription?
    private(set) var audioFormat: AudioStreamBasicDescription?
    private(set) var stopError: Error?

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.withLock { stopError = error }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard buffer.isValid else { return }
        lock.lock()
        defer { lock.unlock() }
        switch type {
        case .screen:
            screenCount += 1
        case .audio:
            audioCount += 1
            if firstAudioTime == nil {
                firstAudioTime = CMSampleBufferGetPresentationTimeStamp(buffer)
                audioFormat = Self.asbd(buffer)
            }
            audioPeak = max(audioPeak, Self.peak(buffer))
        case .microphone:
            micCount += 1
            if firstMicTime == nil {
                firstMicTime = CMSampleBufferGetPresentationTimeStamp(buffer)
                micFormat = Self.asbd(buffer)
            }
            micPeak = max(micPeak, Self.peak(buffer))
        @unknown default:
            break
        }
    }

    static func asbd(_ buffer: CMSampleBuffer) -> AudioStreamBasicDescription? {
        guard let format = CMSampleBufferGetFormatDescription(buffer) else { return nil }
        return CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
    }

    /// Peak absolute amplitude of float32 PCM (all buffers/channels); 0 if not float.
    static func peak(_ buffer: CMSampleBuffer) -> Float {
        guard let asbd = asbd(buffer), asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 else {
            return 0
        }
        var size = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer, bufferListSizeNeededOut: &size, bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0,
            blockBufferOut: nil)
        guard size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: size, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        var block: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: size,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0,
            blockBufferOut: &block)
        guard status == noErr else { return 0 }
        var peak: Float = 0
        for audioBuffer in UnsafeMutableAudioBufferListPointer(list) {
            guard let data = audioBuffer.mData else { continue }
            let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.assumingMemoryBound(to: Float.self)
            for index in 0..<count { peak = max(peak, abs(samples[index])) }
        }
        return peak
    }
}

func decibels(_ peak: Float) -> Double {
    peak > 0 ? 20 * log10(Double(peak)) : -.infinity
}

func formatDb(_ value: Double) -> String {
    value.isInfinite ? "-inf" : String(format: "%.1f", value)
}

func describe(_ asbd: AudioStreamBasicDescription?) -> String {
    guard let asbd else { return "unknown" }
    let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
    let interleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
    return "\(asbd.mSampleRate) Hz, \(asbd.mChannelsPerFrame) ch, "
        + "\(isFloat ? "float" : "int")\(asbd.mBitsPerChannel) "
        + "\(interleaved ? "interleaved" : "non-interleaved")"
}

/// Starts a stream for 6 s, runs `during` 1 s after start, then stops it.
func runStream(filter: SCContentFilter, configuration: SCStreamConfiguration,
               screenOutput: Bool, microphone: Bool, collector: Collector,
               during: (() -> Void)? = nil) async throws {
    let stream = SCStream(filter: filter, configuration: configuration, delegate: collector)
    let queue = DispatchQueue(label: "nastro.probe.capture")
    if screenOutput {
        try stream.addStreamOutput(collector, type: .screen, sampleHandlerQueue: queue)
    }
    try stream.addStreamOutput(collector, type: .audio, sampleHandlerQueue: queue)
    if microphone {
        try stream.addStreamOutput(collector, type: .microphone, sampleHandlerQueue: queue)
    }
    try await stream.startCapture()
    try await Task.sleep(nanoseconds: 1_000_000_000)
    during?()
    try await Task.sleep(nanoseconds: 5_000_000_000)
    try await stream.stopCapture()
}

func baseConfiguration() -> SCStreamConfiguration {
    let configuration = SCStreamConfiguration()
    configuration.capturesAudio = true
    configuration.sampleRate = 48_000
    configuration.channelCount = 2
    return configuration
}

func playGlass() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    process.arguments = ["/System/Library/Sounds/Glass.aiff"]
    do { try process.run() } catch { print("afplay failed: \(error)") }
}

// MARK: - A: window-audio

func windowAudio() async throws {
    requireScreenAccess()
    // SCContentFilter(desktopIndependentWindow:) asserts unless the window server
    // connection is initialised, which a plain command-line tool does not do by itself.
    _ = NSApplication.shared
    let content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true)
    let windows = content.windows.filter {
        $0.windowLayer == 0 && $0.frame.width > 50 && $0.frame.height > 50
    }
    var chosen = windows.first { $0.owningApplication?.bundleIdentifier == "com.apple.finder" }
    var which = "Finder window"
    if chosen == nil {
        chosen = windows.first {
            $0.owningApplication?.bundleIdentifier != "com.apple.finder"
                && $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        which = "no Finder window; fallback to first on-screen window of another app"
    }
    guard let window = chosen else { fail("no on-screen window available") }
    print("window: \(which): \"\(window.title ?? "")\" "
        + "(\(window.owningApplication?.applicationName ?? "?")) \(window.frame)")

    let collector = Collector()
    let configuration = baseConfiguration()
    configuration.width = Int(window.frame.width)
    configuration.height = Int(window.frame.height)
    try await runStream(filter: SCContentFilter(desktopIndependentWindow: window),
                        configuration: configuration, screenOutput: true, microphone: false,
                        collector: collector, during: playGlass)
    let db = decibels(collector.audioPeak)
    print("audio buffers: \(collector.audioCount), video frames: \(collector.screenCount), "
        + "audio format: \(describe(collector.audioFormat))")
    if let error = collector.stopError { print("stream stopped with error: \(error)") }
    print("RESULT A \(db > -40 ? "yes" : "no") peak=\(formatDb(db)) dB "
        + "audioBuffers=\(collector.audioCount) window=\"\(which)\"")
}

// MARK: - B: audio-only

func audioOnly() async throws {
    requireScreenAccess()
    requireMicrophoneAccess()
    let content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true)
    guard let display = content.displays.first else { fail("no display") }
    let collector = Collector()
    let configuration = baseConfiguration()
    configuration.captureMicrophone = true
    configuration.width = 2
    configuration.height = 2
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
    try await runStream(filter: SCContentFilter(display: display, excludingWindows: []),
                        configuration: configuration, screenOutput: false, microphone: true,
                        collector: collector, during: playGlass)
    print("audio buffers: \(collector.audioCount) (peak \(formatDb(decibels(collector.audioPeak))) dB), "
        + "mic buffers: \(collector.micCount) (peak \(formatDb(decibels(collector.micPeak))) dB), "
        + "video frames: \(collector.screenCount)")
    if let error = collector.stopError { print("stream stopped with error: \(error)") }
    let ok = collector.audioCount > 0 && collector.micCount > 0
    print("RESULT B \(ok ? "yes" : "no") audio=\(collector.audioCount) mic=\(collector.micCount)")
}

// MARK: - C: mic-format

func micFormat() async throws {
    requireScreenAccess()
    requireMicrophoneAccess()
    let content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true)
    guard let display = content.displays.first else { fail("no display") }
    let collector = Collector()
    let configuration = baseConfiguration()
    configuration.captureMicrophone = true
    configuration.width = 2
    configuration.height = 2
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
    try await runStream(filter: SCContentFilter(display: display, excludingWindows: []),
                        configuration: configuration, screenOutput: false, microphone: true,
                        collector: collector, during: playGlass)
    print("microphone format: \(describe(collector.micFormat))")
    print("system audio format: \(describe(collector.audioFormat))")
    guard let audio = collector.firstAudioTime, let mic = collector.firstMicTime else {
        print("RESULT C no missing-stream audioBuffers=\(collector.audioCount) "
            + "micBuffers=\(collector.micCount)")
        return
    }
    let deltaMs = abs((audio - mic).seconds) * 1000
    print("first audio pts \(audio.seconds) s, first mic pts \(mic.seconds) s")
    print("RESULT C \(deltaMs < 500 ? "yes" : "no") deltaMs=\(String(format: "%.1f", deltaMs)) "
        + "mic=[\(describe(collector.micFormat))]")
}

// MARK: - D: crash-write and inspect

func solidFrame(width: Int, height: Int, shade: UInt8, at time: CMTime) -> CMSampleBuffer {
    var pixelBuffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any]()]
    precondition(CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                     kCVPixelFormatType_32BGRA, attributes as CFDictionary,
                                     &pixelBuffer) == kCVReturnSuccess)
    let buffer = pixelBuffer!
    CVPixelBufferLockBaseAddress(buffer, [])
    memset(CVPixelBufferGetBaseAddress(buffer)!, Int32(shade),
           CVPixelBufferGetBytesPerRow(buffer) * height)
    CVPixelBufferUnlockBaseAddress(buffer, [])
    var format: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &format)
    var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time,
                                    decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescription: format!,
        sampleTiming: &timing, sampleBufferOut: &sample)
    return sample!
}

func toneBlock(sampleRate: Double, frameIndex: Int64) -> CMSampleBuffer {
    let frames = AVAudioFrameCount(1024)
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    pcm.frameLength = frames
    for channel in 0..<2 {
        let data = pcm.floatChannelData![channel]
        for index in 0..<Int(frames) {
            let t = Double(frameIndex + Int64(index)) / sampleRate
            data[index] = Float(0.3 * sin(2 * Double.pi * 440 * t))
        }
    }
    let time = CMTime(value: frameIndex, timescale: CMTimeScale(sampleRate))
    var sample: CMSampleBuffer?
    CMAudioSampleBufferCreateWithPacketDescriptions(
        allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
        makeDataReadyCallback: nil, refcon: nil, formatDescription: format.formatDescription,
        sampleCount: CMItemCount(frames), presentationTimeStamp: time,
        packetDescriptions: nil, sampleBufferOut: &sample)
    CMSampleBufferSetDataBufferFromAudioBufferList(
        sample!, blockBufferAllocator: kCFAllocatorDefault,
        blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0,
        bufferList: pcm.audioBufferList)
    return sample!
}

/// Writes synthetic video + system audio in real time for 60 s (meant to be killed midway).
func crashWrite(path: String) async throws {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    let spec = VideoSpec(width: 1280, height: 720, fps: 30)
    let writer = try MovieWriter(url: url, video: spec, systemAudio: true, microphone: false)
    let sampleRate = 48_000.0
    let origin = 1000.0
    let started = Date()
    var audioFrame = Int64(origin * sampleRate)
    var frameNumber = 0
    print("crash-write: writing \(path) for 60 s (pid \(getpid()))")
    while true {
        let elapsed = Date().timeIntervalSince(started)
        if elapsed >= 60 { break }
        let videoTime = CMTime(seconds: origin + Double(frameNumber) / 30, preferredTimescale: 30_000)
        writer.append(.video, solidFrame(width: spec.width, height: spec.height,
                                         shade: UInt8(frameNumber % 200 + 20), at: videoTime))
        frameNumber += 1
        // Audio up to the current presentation time.
        while Double(audioFrame) / sampleRate < origin + Double(frameNumber) / 30 {
            writer.append(.systemAudio, toneBlock(sampleRate: sampleRate, frameIndex: audioFrame))
            audioFrame += 1024
        }
        let next = Double(frameNumber) / 30
        let wait = next - Date().timeIntervalSince(started)
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
    }
    let result = try await writer.finish()
    print("crash-write finished normally: \(result)")
}

func inspect(path: String) async throws {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let tracks = try await asset.load(.tracks)
    let duration = try await asset.load(.duration)
    print("video tracks: \(tracks.filter { $0.mediaType == .video }.count)")
    print("audio tracks: \(tracks.filter { $0.mediaType == .audio }.count)")
    print("duration: \(String(format: "%.2f", duration.seconds)) s")
}

/// Prints `<window id> <title>` for each on-screen window owned by `owner` (for
/// `screencapture -l`). Window titles need screen access; ids do not.
func listWindows(owner: String) {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    for window in info where (window[kCGWindowOwnerName as String] as? String) == owner {
        let id = window[kCGWindowNumber as String] as? Int ?? 0
        let title = window[kCGWindowName as String] as? String ?? ""
        print("\(id) \(title)")
    }
}

// MARK: - Dispatch

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fail("usage: NastroProbe window-audio | audio-only | mic-format | crash-write <file> | inspect <file> | windows <owner>")
}
do {
    switch arguments[1] {
    case "window-audio": try await windowAudio()
    case "audio-only": try await audioOnly()
    case "mic-format": try await micFormat()
    case "crash-write":
        guard arguments.count >= 3 else { fail("usage: crash-write <file>") }
        try await crashWrite(path: arguments[2])
    case "inspect":
        guard arguments.count >= 3 else { fail("usage: inspect <file>") }
        try await inspect(path: arguments[2])
    case "windows":
        guard arguments.count >= 3 else { fail("usage: windows <owner>") }
        listWindows(owner: arguments[2])
    default:
        fail("unknown subcommand \(arguments[1])")
    }
} catch {
    fail("error: \(error)")
}
