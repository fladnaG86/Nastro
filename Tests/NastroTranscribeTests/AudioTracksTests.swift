import AVFoundation
import XCTest
import NastroCore
@testable import NastroTranscribe

final class AudioTracksTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("AudioTracksTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func assertCAF(_ url: URL, duration: Double, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(url.pathExtension, "caf", file: file, line: line)
        let audio = try AVAudioFile(forReading: url)
        XCTAssertEqual(audio.fileFormat.sampleRate, 16_000, file: file, line: line)
        XCTAssertEqual(audio.fileFormat.channelCount, 1, file: file, line: line)
        XCTAssertEqual(Double(audio.length) / audio.fileFormat.sampleRate, duration, accuracy: 0.1, file: file, line: line)
    }

    func testTwoTrackFileGivesOthersThenMe() async throws {
        let recording = dir.appendingPathComponent("two.m4a")
        try await TestAudio.makeFile(at: recording, amplitudes: [0.5, 0], duration: 2)
        let out = dir.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let streams = try await AudioTracks.extract(from: recording, into: out)

        XCTAssertEqual(streams.count, 2)
        XCTAssertEqual(streams.map(\.speaker), [.others, .me])
        XCTAssertNotEqual(streams[0].file, streams[1].file)
        for stream in streams {
            try assertCAF(stream.file, duration: 2)
            XCTAssertEqual(stream.duration, 2, accuracy: 0.1)
        }
    }

    func testSingleTrackHasNoSpeaker() async throws {
        let recording = dir.appendingPathComponent("one.m4a")
        try await TestAudio.makeFile(at: recording, amplitudes: [0.5], duration: 1)

        let streams = try await AudioTracks.extract(from: recording, into: dir)

        XCTAssertEqual(streams.count, 1)
        XCTAssertNil(streams[0].speaker)
        try assertCAF(streams[0].file, duration: 1)
    }

    func testNoAudioThrowsNoAudio() async throws {
        let fake = dir.appendingPathComponent("fake.mp4")
        try Data("not a movie".utf8).write(to: fake)

        do {
            _ = try await AudioTracks.extract(from: fake, into: dir)
            XCTFail("expected noAudio")
        } catch let error as SummaryError {
            XCTAssertEqual(error, .noAudio)
        }
    }
}
