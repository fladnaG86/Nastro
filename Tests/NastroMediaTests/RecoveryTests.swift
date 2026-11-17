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

    func testStaleFinalizingFilesAreRemovedAndWorkFileKeepsItsName() async throws {
        // F5: an interrupted finalization left "A.nastro-finalizing.mp4" next to its work file,
        // and an orphan "Z.nastro-finalizing.m4a" → both are deleted, A is recovered as "A.mp4"
        // (not "A 2.mp4").
        let work = file("A.nastro-partial.mov")
        try await TestMedia.makeWorkFile(at: work, video: true, audio: [
            .init(kind: .systemAudio, sampleRate: 48_000, channels: 2),
        ], duration: 2)
        try Data("junk".utf8).write(to: file("A.nastro-finalizing.mp4"))
        try Data("junk".utf8).write(to: file("Z.nastro-finalizing.m4a"))

        let outcomes = await Recovery.run(in: directory, keepSeparateTracks: false)

        XCTAssertEqual(outcomes, [.recovered(file("A.mp4"))])
        XCTAssertFalse(FileManager.default.fileExists(atPath: file("A.nastro-finalizing.mp4").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file("Z.nastro-finalizing.m4a").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.path))
        let tracks = try await TestMedia.tracks(of: file("A.mp4"))
        XCTAssertEqual(tracks.video, 1)
    }

    func testNotEnoughRoomLeavesWorkFileUntouched() async throws {
        // F4: free space below the work file's size → [.noRoom(work)], nothing renamed,
        // nothing written; with room at the next launch it is recovered.
        let work = file("D.nastro-partial.mov")
        try await TestMedia.makeWorkFile(at: work, video: true, audio: [
            .init(kind: .systemAudio, sampleRate: 48_000, channels: 2),
        ], duration: 2)
        let size = try XCTUnwrap(
            (try FileManager.default.attributesOfItem(atPath: work.path))[.size] as? NSNumber).int64Value
        let original = try Data(contentsOf: work)

        let first = await Recovery.run(in: directory, keepSeparateTracks: false,
                                       freeBytes: { _ in size - 1 })

        XCTAssertEqual(first, [.noRoom(work)])
        XCTAssertEqual(try Data(contentsOf: work), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path),
                       ["D.nastro-partial.mov"])

        let second = await Recovery.run(in: directory, keepSeparateTracks: false,
                                        freeBytes: { _ in size })
        XCTAssertEqual(second, [.recovered(file("D.mp4"))])
    }

    func testOnlyUnreadableOrTracklessFilesAreMarkedDamaged() async throws {
        // F4: .exportFailed leaves the work file as it is (retried at the next launch) and
        // reports .failed; .unreadable and .noTracks rename it to ".nastro-damaged.mov".
        let cases: [(FinalizeError, String, RecoveryOutcome)] = [
            (.exportFailed, "E", .failed(file("E.nastro-partial.mov"))),
            (.unreadable, "F", .damaged(file("F.nastro-damaged.mov"))),
            (.noTracks, "G", .damaged(file("G.nastro-damaged.mov"))),
        ]
        for (error, name, expected) in cases {
            let work = file("\(name).nastro-partial.mov")
            try Data("work \(name)".utf8).write(to: work)
            let outcomes = await Recovery.run(in: directory, keepSeparateTracks: false,
                                              freeBytes: { _ in nil },
                                              finalize: { _, _, _ in throw error })
            XCTAssertEqual(outcomes, [expected], "\(error)")
            if error == .exportFailed {
                XCTAssertEqual(try? Data(contentsOf: work), Data("work \(name)".utf8))
            }
            try? FileManager.default.removeItem(at: work)
            try? FileManager.default.removeItem(at: file("\(name).nastro-damaged.mov"))
        }
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
