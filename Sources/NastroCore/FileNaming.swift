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

    public static func isWorkFile(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix(workSuffix)
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
