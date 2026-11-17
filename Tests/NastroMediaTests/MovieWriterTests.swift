import AVFoundation
import CoreMedia
import XCTest
@testable import NastroMedia

final class MovieWriterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var workURL: URL { directory.appendingPathComponent("work.mov") }
    private let spec = VideoSpec(width: 640, height: 360, fps: 30)

    private struct AudioSource {
        let kind: SampleKind
        let sampleRate: Double
        let channels: Int
        /// Seconds, relative to the feed origin.
        var from: Double = 0
        var until: Double
    }

    /// Feeds frames (640×360 at 30 fps) and 1024-frame audio blocks to `writer`, interleaved
    /// in presentation order. Times are `origin + offset` seconds; `videoTimes` are offsets.
    private func feed(_ writer: MovieWriter, origin: Double, videoTimes: [Double],
                      audio: [AudioSource]) {
        var events: [(time: CMTime, kind: SampleKind, buffer: () -> CMSampleBuffer)] = []
        for offset in videoTimes {
            let time = CMTime(seconds: origin + offset, preferredTimescale: 30_000)
            events.append((time, .video, { [spec] in
                TestMedia.videoFrame(width: spec.width, height: spec.height, at: time)
            }))
        }
        for source in audio {
            let rate = Int64(source.sampleRate)
            var frame = Int64((origin + source.from) * source.sampleRate)
            let end = Int64((origin + source.until) * source.sampleRate)
            while frame < end {
                let time = CMTime(value: frame, timescale: CMTimeScale(rate))
                let block = CMTime(value: 1024, timescale: CMTimeScale(rate))
                events.append((time, source.kind, {
                    TestMedia.tone(sampleRate: source.sampleRate, channels: source.channels,
                                   at: time, duration: block)
                }))
                frame += 1024
            }
        }
        events.sort { CMTimeCompare($0.time, $1.time) < 0 }
        for event in events {
            writer.append(event.kind, event.buffer())
        }
    }

    private func frames(from start: Double, until end: Double) -> [Double] {
        stride(from: start, to: end, by: 1.0 / 30).map { $0 }
    }

    private func writtenDuration(_ result: WriteResult) throws -> Double {
        guard case let .written(duration) = result else {
            XCTFail("expected .written, got \(result)")
            throw TestMedia.Failure("not written")
        }
        return duration
    }

    func testVideoWithTwoAudioSources() async throws {
        // video + sistema 48k/2ch + mic 48k/1ch → .written(duration ≈ 3 ± 0.2)
        // tracks: video 1, audio 2
        let writer = try MovieWriter(url: workURL, video: spec, systemAudio: true, microphone: true)
        feed(writer, origin: 1000, videoTimes: frames(from: 0, until: 3), audio: [
            AudioSource(kind: .systemAudio, sampleRate: 48_000, channels: 2, until: 3),
            AudioSource(kind: .microphone, sampleRate: 48_000, channels: 1, until: 3),
        ])
        let duration = try writtenDuration(try await writer.finish())
        XCTAssertEqual(duration, 3, accuracy: 0.2)
        XCTAssertNil(writer.failure)
        XCTAssertEqual(writer.sourcesWithoutTrack, [])
        XCTAssertEqual(writer.degradedSources, [])

        let tracks = try await TestMedia.tracks(of: workURL)
        XCTAssertEqual(tracks.video, 1)
        XCTAssertEqual(tracks.audio, 2)
        XCTAssertEqual(tracks.duration, 3, accuracy: 0.2)
    }

    func testLateSourceIsReportedWithoutTrack() async throws {
        // Fix round 1, finding 2: mic expected, first mic buffer 3 s after the first frame
        // → sourcesWithoutTrack == [.microphone], audio 1, no failure.
        let writer = try MovieWriter(url: workURL, video: spec, systemAudio: true, microphone: true)
        XCTAssertEqual(writer.sourcesWithoutTrack, [], "empty before the session starts")
        feed(writer, origin: 1000, videoTimes: frames(from: 0, until: 5), audio: [
            AudioSource(kind: .systemAudio, sampleRate: 48_000, channels: 2, until: 5),
            AudioSource(kind: .microphone, sampleRate: 48_000, channels: 1, from: 3, until: 5),
        ])
        XCTAssertEqual(writer.sourcesWithoutTrack, [.microphone], "readable while recording")
        _ = try writtenDuration(try await writer.finish())
        XCTAssertNil(writer.failure)
        XCTAssertEqual(writer.sourcesWithoutTrack, [.microphone])

        let tracks = try await TestMedia.tracks(of: workURL)
        XCTAssertEqual(tracks.audio, 1)
    }

    func testMicrophoneFormatChangeDegradesOnlyThatSource() async throws {
        // Fix round 1, finding 3a: mic 48 kHz mono 2 s then 16 kHz mono 2 s, video + system 4 s
        // → no failure, degradedSources == [.microphone], video ≈ 4 s, two audio tracks.
        let writer = try MovieWriter(url: workURL, video: spec, systemAudio: true, microphone: true)
        feed(writer, origin: 1000, videoTimes: frames(from: 0, until: 4), audio: [
            AudioSource(kind: .systemAudio, sampleRate: 48_000, channels: 2, until: 4),
            AudioSource(kind: .microphone, sampleRate: 48_000, channels: 1, until: 2),
            AudioSource(kind: .microphone, sampleRate: 16_000, channels: 1, from: 2, until: 4),
        ])
        let duration = try writtenDuration(try await writer.finish())
        XCTAssertNil(writer.failure)
        XCTAssertEqual(writer.degradedSources, [.microphone])
        XCTAssertEqual(duration, 4, accuracy: 0.2)

        let tracks = try await TestMedia.tracks(of: workURL)
        XCTAssertEqual(tracks.audio, 2)
        let asset = AVURLAsset(url: workURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1)
        let range = try await videoTracks[0].load(.timeRange)
        XCTAssertEqual(range.duration.seconds, 4, accuracy: 0.2)
    }

    func testBackwardsAudioTimestampIsDropped() async throws {
        // Fix round 1, finding 3b: one system-audio buffer earlier than the previous one in
        // the middle of 3 s → no failure, duration ≈ 3, degradedSources empty.
        let writer = try MovieWriter(url: workURL, video: spec, systemAudio: true, microphone: false)
        feed(writer, origin: 1000, videoTimes: frames(from: 0, until: 1.5), audio: [
            AudioSource(kind: .systemAudio, sampleRate: 48_000, channels: 2, until: 1.5),
        ])
        writer.append(.systemAudio, TestMedia.tone(
            sampleRate: 48_000, channels: 2, at: CMTime(value: 1001 * 48_000, timescale: 48_000),
            duration: CMTime(value: 1024, timescale: 48_000)))
        feed(writer, origin: 1000, videoTimes: frames(from: 1.5, until: 3), audio: [
            AudioSource(kind: .systemAudio, sampleRate: 48_000, channels: 2, from: 1.5, until: 3),
        ])
        let duration = try writtenDuration(try await writer.finish())
        XCTAssertNil(writer.failure)
        XCTAssertEqual(duration, 3, accuracy: 0.2)
        XCTAssertEqual(writer.degradedSources, [])
    }

    func testRepeatedFinishReturnsSameOutcomeAndKeepsFile() async throws {
        // Fix round 1, finding 1: a second finish() (sequential or concurrent) returns the
        // first outcome and never deletes the recording.
        let sequential = try MovieWriter(url: workURL, video: spec, systemAudio: true,
                                         microphone: false)
        feed(sequential, origin: 1000, videoTimes: frames(from: 0, until: 1), audio: [
            AudioSource(kind: .systemAudio, sampleRate: 48_000, channels: 2, until: 1),
        ])
        let first = try await sequential.finish()
        let second = try await sequential.finish()
        XCTAssertEqual(second, first)
        _ = try writtenDuration(first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workURL.path))

        let concurrentURL = directory.appendingPathComponent("concurrent.mov")
        let concurrent = try MovieWriter(url: concurrentURL, video: spec, systemAudio: true,
                                         microphone: false)
        feed(concurrent, origin: 1000, videoTimes: frames(from: 0, until: 1), audio: [
            AudioSource(kind: .systemAudio, sampleRate: 48_000, channels: 2, until: 1),
        ])
        async let a = concurrent.finish()
        async let b = concurrent.finish()
        let (resultA, resultB) = try await (a, b)
        XCTAssertEqual(resultA, resultB)
        _ = try writtenDuration(resultA)
        XCTAssertTrue(FileManager.default.fileExists(atPath: concurrentURL.path))
        let tracks = try await TestMedia.tracks(of: concurrentURL)
        XCTAssertEqual(tracks.video, 1)
    }

    func testAudioOnly() async throws {
        // video: nil → tracks: video 0, audio 2, durata ≈ 3
        let writer = try MovieWriter(url: workURL, video: nil, systemAudio: true, microphone: true)
        feed(writer, origin: 1000, videoTimes: [], audio: [
            AudioSource(kind: .systemAudio, sampleRate: 48_000, channels: 2, until: 3),
            AudioSource(kind: .microphone, sampleRate: 48_000, channels: 1, until: 3),
        ])
        let duration = try writtenDuration(try await writer.finish())
        XCTAssertEqual(duration, 3, accuracy: 0.2)

        let tracks = try await TestMedia.tracks(of: workURL)
        XCTAssertEqual(tracks.video, 0)
        XCTAssertEqual(tracks.audio, 2)
        XCTAssertEqual(tracks.duration, 3, accuracy: 0.2)
    }

    func testMicrophoneNativeFormatIsKept() async throws {      // Review Focus 1
        // mic 16 kHz mono + sistema 48 kHz stereo → audioFormats contiene (16000,1) e (48000,2); durata ≈ 3
        let writer = try MovieWriter(url: workURL, video: spec, systemAudio: true, microphone: true)
        feed(writer, origin: 1000, videoTimes: frames(from: 0, until: 3), audio: [
            AudioSource(kind: .systemAudio, sampleRate: 48_000, channels: 2, until: 3),
            AudioSource(kind: .microphone, sampleRate: 16_000, channels: 1, until: 3),
        ])
        let duration = try writtenDuration(try await writer.finish())
        XCTAssertEqual(duration, 3, accuracy: 0.2)

        let formats = try await TestMedia.audioFormats(of: workURL)
        XCTAssertEqual(formats.count, 2)
        XCTAssertTrue(formats.contains { $0.sampleRate == 16_000 && $0.channels == 1 },
                      "formats: \(formats)")
        XCTAssertTrue(formats.contains { $0.sampleRate == 48_000 && $0.channels == 2 },
                      "formats: \(formats)")
        let tracks = try await TestMedia.tracks(of: workURL)
        XCTAssertEqual(tracks.duration, 3, accuracy: 0.2)
    }

    func testEightKilohertzMicrophoneIsKept() async throws {
        // Controller decision 1: worst headset case, AAC max 24 kb/s at 8 kHz mono.
        // mic 8 kHz mono + sistema 48 kHz stereo → audioFormats contiene (8000,1) e (48000,2); durata ≈ 3
        let writer = try MovieWriter(url: workURL, video: spec, systemAudio: true, microphone: true)
        feed(writer, origin: 1000, videoTimes: frames(from: 0, until: 3), audio: [
            AudioSource(kind: .systemAudio, sampleRate: 48_000, channels: 2, until: 3),
            AudioSource(kind: .microphone, sampleRate: 8_000, channels: 1, until: 3),
        ])
        let duration = try writtenDuration(try await writer.finish())
        XCTAssertEqual(duration, 3, accuracy: 0.2)

        let formats = try await TestMedia.audioFormats(of: workURL)
        XCTAssertEqual(formats.count, 2)
        XCTAssertTrue(formats.contains { $0.sampleRate == 8_000 && $0.channels == 1 },
                      "formats: \(formats)")
        XCTAssertTrue(formats.contains { $0.sampleRate == 48_000 && $0.channels == 2 },
                      "formats: \(formats)")
    }

    func testStaticScreenVideoLastsAsLongAsAudio() async throws {  // Review Focus 2
        // un solo fotogramma a t=0, audio fino a t=5 → durata della traccia video ≥ 4.8
        let writer = try MovieWriter(url: workURL, video: spec, systemAudio: true, microphone: false)
        feed(writer, origin: 0, videoTimes: [0], audio: [
            AudioSource(kind: .systemAudio, sampleRate: 48_000, channels: 2, until: 5),
        ])
        _ = try writtenDuration(try await writer.finish())

        let asset = AVURLAsset(url: workURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1)
        let range = try await videoTracks[0].load(.timeRange)
        XCTAssertGreaterThanOrEqual(range.duration.seconds, 4.8)
    }

    func testFinishWithoutSamplesIsEmptyAndLeavesNoFile() async throws {  // Review Focus 3
        // finish() == .empty ; FileManager.fileExists(url) == false
        let writer = try MovieWriter(url: workURL, video: spec, systemAudio: true, microphone: true)
        let result = try await writer.finish()
        XCTAssertEqual(result, .empty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workURL.path))
    }

    func testMissingSourceGetsNoTrack() async throws {
        // microphone: true ma nessun campione mic → tracks.audio == 1, nessun errore
        let writer = try MovieWriter(url: workURL, video: spec, systemAudio: true, microphone: true)
        feed(writer, origin: 1000, videoTimes: frames(from: 0, until: 3), audio: [
            AudioSource(kind: .systemAudio, sampleRate: 48_000, channels: 2, until: 3),
        ])
        _ = try writtenDuration(try await writer.finish())
        XCTAssertNil(writer.failure)

        let tracks = try await TestMedia.tracks(of: workURL)
        XCTAssertEqual(tracks.video, 1)
        XCTAssertEqual(tracks.audio, 1)
    }

    func testMissingSourceDelaysStartByTheWait() async throws {
        // Controller decision 2: only the newest frame is held during the format wait, so a
        // missing source makes the recording start at the end of the 2 s wait.
        // mic expected, never delivered; video + system t0…t0+5 → no error, audio 1, video ≈ 3 ± 0.3
        let writer = try MovieWriter(url: workURL, video: spec, systemAudio: true, microphone: true)
        feed(writer, origin: 1000, videoTimes: frames(from: 0, until: 5), audio: [
            AudioSource(kind: .systemAudio, sampleRate: 48_000, channels: 2, until: 5),
        ])
        let duration = try writtenDuration(try await writer.finish())
        XCTAssertEqual(duration, 3, accuracy: 0.3)
        XCTAssertNil(writer.failure)

        let tracks = try await TestMedia.tracks(of: workURL)
        XCTAssertEqual(tracks.audio, 1)
        let asset = AVURLAsset(url: workURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1)
        let range = try await videoTracks[0].load(.timeRange)
        XCTAssertEqual(range.duration.seconds, 3, accuracy: 0.3)
    }

    func testAudioBeforeFirstFrameIsDropped() async throws {
        // audio da t=0, primo fotogramma a t=1, tutto fino a t=3 → durata ≈ 2 ± 0.2
        let writer = try MovieWriter(url: workURL, video: spec, systemAudio: true, microphone: true)
        feed(writer, origin: 1000, videoTimes: frames(from: 1, until: 3), audio: [
            AudioSource(kind: .systemAudio, sampleRate: 48_000, channels: 2, until: 3),
            AudioSource(kind: .microphone, sampleRate: 48_000, channels: 1, until: 3),
        ])
        let duration = try writtenDuration(try await writer.finish())
        XCTAssertEqual(duration, 2, accuracy: 0.2)

        let tracks = try await TestMedia.tracks(of: workURL)
        XCTAssertEqual(tracks.video, 1)
        XCTAssertEqual(tracks.audio, 2)
        XCTAssertEqual(tracks.duration, 2, accuracy: 0.2)
    }
}
