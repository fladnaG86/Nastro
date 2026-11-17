import Foundation
import NastroCore

public enum RecoveryOutcome: Equatable, Sendable { case recovered(URL), damaged(URL) }

/// Finalizes work files left behind by an interrupted recording.
public enum Recovery {
    public static let damagedSuffix = ".nastro-damaged.mov"

    /// Looks for work files in `folder` and turns each into a final file, deleting the work
    /// file on success. A work file that cannot be finalized is renamed with `damagedSuffix`
    /// so it is not retried at the next launch. Never throws.
    public static func run(in folder: URL, keepSeparateTracks: Bool) async -> [RecoveryOutcome] {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else {
            return []
        }
        var outcomes: [RecoveryOutcome] = []
        for name in names.sorted() {
            let work = folder.appendingPathComponent(name)
            guard FileNaming.isWorkFile(work) else { continue }
            let hasVideo = await Finalizer.hasVideo(work)
            let final = FileNaming.finalURL(forWorkFile: work, hasVideo: hasVideo) {
                fileManager.fileExists(atPath: $0.path)
            }
            do {
                try await Finalizer.finalize(workFile: work, to: final,
                                             keepSeparateTracks: keepSeparateTracks)
                try? fileManager.removeItem(at: work)
                outcomes.append(.recovered(final))
            } catch {
                outcomes.append(.damaged(markDamaged(work, name: name, in: folder)))
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
