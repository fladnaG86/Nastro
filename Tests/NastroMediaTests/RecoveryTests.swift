import Foundation
import XCTest
@testable import NastroMedia

final class RecoveryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(_ name: String) -> URL { directory.appendingPathComponent(name) }

    func testRecoversLeftoverAndDeletesWorkFile() async throws {
        // cartella con "A.nastro-partial.mov" valido (con video) → [.recovered(.../A.mp4)] ;
        // A.nastro-partial.mov non esiste più
        let work = file("A.nastro-partial.mov")
        try await TestMedia.makeWorkFile(at: work, video: true, audio: [
            .init(kind: .systemAudio, sampleRate: 48_000, channels: 2),
            .init(kind: .microphone, sampleRate: 16_000, channels: 1),
        ], duration: 2)

        let outcomes = await Recovery.run(in: directory, keepSeparateTracks: false)

        XCTAssertEqual(outcomes, [.recovered(file("A.mp4"))])
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file("A.mp4").path))
    }

    func testDamagedFileIsRenamedAndNotRetried() async throws {      // Review Focus 5
        // "B.nastro-partial.mov" da 0 byte → [.damaged(.../B.nastro-damaged.mov)]
        // seconda chiamata a run → []
        let work = file("B.nastro-partial.mov")
        XCTAssertTrue(FileManager.default.createFile(atPath: work.path, contents: Data()))

        let first = await Recovery.run(in: directory, keepSeparateTracks: false)
        XCTAssertEqual(first, [.damaged(file("B.nastro-damaged.mov"))])
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file("B.nastro-damaged.mov").path))

        let second = await Recovery.run(in: directory, keepSeparateTracks: false)
        XCTAssertEqual(second, [])
    }

    func testIgnoresOtherFiles() async throws {
        // cartella con solo "C.mp4" → []
        XCTAssertTrue(FileManager.default.createFile(atPath: file("C.mp4").path,
                                                     contents: Data([1, 2, 3])))

        let outcomes = await Recovery.run(in: directory, keepSeparateTracks: false)

        XCTAssertEqual(outcomes, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: file("C.mp4").path))
    }
}
