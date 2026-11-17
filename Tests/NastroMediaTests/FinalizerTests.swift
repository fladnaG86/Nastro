import AVFoundation
import XCTest
@testable import NastroMedia

final class FinalizerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinalizerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var workURL: URL { directory.appendingPathComponent("work.nastro-partial.mov") }

    private func makeWorkWithBothSources(
        system: ClosedRange<Double>? = nil, mic: ClosedRange<Double>? = nil
    ) async throws {
        try await TestMedia.makeWorkFile(at: workURL, video: true, audio: [
            .init(kind: .systemAudio, sampleRate: 48_000, channels: 2, toneRange: system),
            .init(kind: .microphone, sampleRate: 16_000, channels: 1, toneRange: mic),
        ], duration: 3)
    }

    func testMergesAudioAndKeepsVideo() async throws {
        // file di lavoro 3 s: video + sistema 48k/2ch + mic 16k/1ch → final .mp4
        // tracks: video 1, audio 1 ; durata ≈ 3 ± 0.2 ; il codec video è ancora HEVC ('hvc1')
        try await makeWorkWithBothSources()
        let final = directory.appendingPathComponent("final.mp4")

        try await Finalizer.finalize(workFile: workURL, to: final, keepSeparateTracks: false)

        let tracks = try await TestMedia.tracks(of: final)
        XCTAssertEqual(tracks.video, 1)
        XCTAssertEqual(tracks.audio, 1)
        XCTAssertEqual(tracks.duration, 3, accuracy: 0.2)
        let codec = try await TestMedia.videoCodec(of: final)
        XCTAssertEqual(codec, "hvc1")
    }

    func testMergedAudioContainsBothSources() async throws {
        // sistema: tono solo in 0…1 s ; mic: tono solo in 2…3 s
        // nel file finale il picco in 0…1 s e in 2…3 s è > -20 dB, in 1.2…1.8 s è < -50 dB
        try await makeWorkWithBothSources(system: 0...1, mic: 2...3)
        let final = directory.appendingPathComponent("final.mp4")

        try await Finalizer.finalize(workFile: workURL, to: final, keepSeparateTracks: false)

        let first = try await TestMedia.peakLevel(of: final, from: 0, to: 1)
        let last = try await TestMedia.peakLevel(of: final, from: 2, to: 3)
        let middle = try await TestMedia.peakLevel(of: final, from: 1.2, to: 1.8)
        XCTAssertGreaterThan(first, -20)
        XCTAssertGreaterThan(last, -20)
        XCTAssertLessThan(middle, -50)
    }

    func testKeepSeparateTracks() async throws {
        // keepSeparateTracks: true → audio 2
        try await makeWorkWithBothSources()
        let final = directory.appendingPathComponent("final.mp4")

        try await Finalizer.finalize(workFile: workURL, to: final, keepSeparateTracks: true)

        let tracks = try await TestMedia.tracks(of: final)
        XCTAssertEqual(tracks.video, 1)
        XCTAssertEqual(tracks.audio, 2)
    }

    func testAudioOnlyToM4A() async throws {
        // video 0, audio 1, estensione m4a leggibile
        try await TestMedia.makeWorkFile(at: workURL, video: false, audio: [
            .init(kind: .systemAudio, sampleRate: 48_000, channels: 2),
            .init(kind: .microphone, sampleRate: 16_000, channels: 1),
        ], duration: 3)
        let final = directory.appendingPathComponent("final.m4a")

        try await Finalizer.finalize(workFile: workURL, to: final, keepSeparateTracks: false)

        let tracks = try await TestMedia.tracks(of: final)
        XCTAssertEqual(tracks.video, 0)
        XCTAssertEqual(tracks.audio, 1)
        XCTAssertEqual(tracks.duration, 3, accuracy: 0.2)
        let hasVideo = await Finalizer.hasVideo(final)
        XCTAssertFalse(hasVideo)
    }

    func testUnreadableWorkFileThrowsAndLeavesNoOutput() async throws {
        // file di lavoro da 0 byte → throws FinalizeError.unreadable ; final non esiste ;
        // il file di lavoro esiste ancora
        XCTAssertTrue(FileManager.default.createFile(atPath: workURL.path, contents: Data()))
        let final = directory.appendingPathComponent("final.mp4")

        do {
            try await Finalizer.finalize(workFile: workURL, to: final, keepSeparateTracks: false)
            XCTFail("expected FinalizeError.unreadable")
        } catch let error as FinalizeError {
            XCTAssertEqual(error, .unreadable)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: final.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workURL.path))
    }
}
