import Foundation

public enum FileNaming {
    public static let workSuffix = ".nastro-partial.mov"

    public static func baseName(date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return f.string(from: date) + " Call"
    }

    public static func finalURL(folder: URL, date: Date, timeZone: TimeZone,
                                hasVideo: Bool, exists: (URL) -> Bool) -> URL {
        unique(folder: folder, base: baseName(date: date, timeZone: timeZone), hasVideo: hasVideo, exists: exists)
    }

    public static func workURL(forFinal url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + workSuffix)
    }

    /// A final name is taken if the final file, its work file or its finalizing file exists: a
    /// work file kept after a failed or skipped finalization must never be reused (overwritten
    /// or deleted) by a new recording, and a finalization in progress will claim the name.
    /// Pass this as the `exists` of `finalURL(folder:…)` when starting a recording.
    public static func isTaken(final url: URL, exists: (URL) -> Bool) -> Bool {
        exists(url) || exists(workURL(forFinal: url)) || exists(finalizingURL(forFinal: url))
    }

    public static func isWorkFile(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix(workSuffix)
    }

    /// Placed before the extension of the temporary file a finalization writes
    /// ("<name>.nastro-finalizing.mp4" / ".m4a"); it is renamed to the final name only once
    /// complete. Never anyone's only copy: its work file exists until the rename succeeded.
    public static let finalizingSuffix = ".nastro-finalizing"

    public static func finalizingURL(forFinal url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(
            url.deletingPathExtension().lastPathComponent + finalizingSuffix + "." + url.pathExtension)
    }

    public static func isFinalizingFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return ["mp4", "m4a"].contains { name.hasSuffix(finalizingSuffix + "." + $0) }
    }

    public static func finalURL(forWorkFile url: URL, hasVideo: Bool,
                                exists: (URL) -> Bool) -> URL {
        let name = url.lastPathComponent
        let base = name.hasSuffix(workSuffix) ? String(name.dropLast(workSuffix.count)) : url.deletingPathExtension().lastPathComponent
        return unique(folder: url.deletingLastPathComponent(), base: base, hasVideo: hasVideo, exists: exists)
    }

    private static func unique(folder: URL, base: String, hasVideo: Bool, exists: (URL) -> Bool) -> URL {
        let ext = hasVideo ? "mp4" : "m4a"
        var candidate = folder.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}

public enum DestinationError: Error, Equatable { case cannotCreate, notWritable }

public enum Destination {
    public static func prepare(_ folder: URL, fileManager: FileManager = .default) throws {
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw DestinationError.cannotCreate
        }
        guard fileManager.isWritableFile(atPath: folder.path) else { throw DestinationError.notWritable }
    }
}
