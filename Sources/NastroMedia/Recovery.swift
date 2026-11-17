import Foundation
import NastroCore

public enum RecoveryOutcome: Equatable, Sendable {
    case recovered(URL), damaged(URL)
    /// Not enough free space to finalize: the work file is left untouched (retried next launch).
    case noRoom(URL)
    /// Finalization failed for a reason that may pass: the work file is left untouched
    /// (retried next launch).
    case failed(URL)
}

/// Finalizes work files left behind by an interrupted recording.
public enum Recovery {
    public static let damagedSuffix = ".nastro-damaged.mov"

    /// Deletes leftover finalizing files in `folder`, then turns each work file into a final
    /// file, deleting the work file on success. A work file that cannot be read or has no
    /// track is renamed with `damagedSuffix` so it is not retried at the next launch. A work
    /// file without room to finalize (`freeBytes` of the folder below its size) or whose
    /// finalization failed otherwise is left untouched and retried at the next launch.
    /// Never throws.
    public static func run(in folder: URL, keepSeparateTracks: Bool,
                           freeBytes: (URL) -> Int64? = Recovery.volumeFreeBytes) async -> [RecoveryOutcome] {
        await run(in: folder, keepSeparateTracks: keepSeparateTracks, freeBytes: freeBytes,
                  finalize: Finalizer.finalize(workFile:to:keepSeparateTracks:))
    }

    /// Free space for important data on `folder`'s volume; nil if unknown.
    public static func volumeFreeBytes(_ folder: URL) -> Int64? {
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Test seam: the finalization step.
    typealias Finalize = (_ workFile: URL, _ final: URL, _ keepSeparateTracks: Bool) async throws -> Void

    static func run(in folder: URL, keepSeparateTracks: Bool, freeBytes: (URL) -> Int64?,
                    finalize: Finalize) async -> [RecoveryOutcome] {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else {
            return []
        }
        // Temporary files of an interrupted finalization: never anyone's only copy (the work
        // file is deleted only after the rename to the final name), so they go first.
        for name in names {
            let url = folder.appendingPathComponent(name)
            if FileNaming.isFinalizingFile(url) { try? fileManager.removeItem(at: url) }
        }
        var outcomes: [RecoveryOutcome] = []
        for name in names.sorted() {
            let work = folder.appendingPathComponent(name)
            guard FileNaming.isWorkFile(work) else { continue }
            let size = ((try? fileManager.attributesOfItem(atPath: work.path))?[.size] as? NSNumber)?.int64Value ?? 0
            guard RecordingRules.hasRoomToFinalize(freeBytes: freeBytes(folder), workFileBytes: size) else {
                outcomes.append(.noRoom(work))
                continue
            }
            let hasVideo = await Finalizer.hasVideo(work)
            let final = FileNaming.finalURL(forWorkFile: work, hasVideo: hasVideo) {
                fileManager.fileExists(atPath: $0.path)
            }
            do {
                try await finalize(work, final, keepSeparateTracks)
                try? fileManager.removeItem(at: work)
                outcomes.append(.recovered(final))
            } catch FinalizeError.unreadable, FinalizeError.noTracks {
                outcomes.append(.damaged(markDamaged(work, name: name, in: folder)))
            } catch {
                // May pass (e.g. a write error): keep the work file as it is for the next launch.
                outcomes.append(.failed(work))
            }
        }
        return outcomes
    }

    /// Renames `work` replacing `workSuffix` with `damagedSuffix` (numbered if that name is
    /// taken). Returns the new URL, or `work` itself if the rename failed.
    private static func markDamaged(_ work: URL, name: String, in folder: URL) -> URL {
        let base = String(name.dropLast(FileNaming.workSuffix.count))
        var candidate = folder.appendingPathComponent(base + damagedSuffix)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(number)\(damagedSuffix)")
            number += 1
        }
        do {
            try FileManager.default.moveItem(at: work, to: candidate)
            return candidate
        } catch {
            return work
        }
    }
}
