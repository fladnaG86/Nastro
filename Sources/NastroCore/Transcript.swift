import Foundation

public enum Speaker: Sendable, Equatable {
    case me, others

    public var label: String {
        switch self {
        case .me: return "Io"
        case .others: return "Altri"
        }
    }
}

public struct TranscriptSegment: Sendable, Equatable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var speaker: Speaker?

    public init(start: TimeInterval, end: TimeInterval, text: String, speaker: Speaker?) {
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
    }
}

public enum Transcript {
    private static let joinGap: TimeInterval = 2.0
    private static let maxJoinedLength = 600

    /// Flattens the streams, orders them by start time (stable), drops blank segments and joins
    /// consecutive segments of the same speaker that are close in time.
    public static func merge(_ streams: [[TranscriptSegment]]) -> [TranscriptSegment] {
        let sorted = streams.flatMap { $0 }.enumerated()
            .sorted { $0.element.start != $1.element.start ? $0.element.start < $1.element.start : $0.offset < $1.offset }
            .map(\.element)
        var result: [TranscriptSegment] = []
        for var segment in sorted {
            segment.text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if segment.text.isEmpty { continue }
            if var previous = result.last, previous.speaker == segment.speaker,
               segment.start - previous.end <= joinGap,
               previous.text.count + 1 + segment.text.count <= maxJoinedLength {
                previous.text += " " + segment.text
                previous.end = max(previous.end, segment.end)
                result[result.count - 1] = previous
            } else {
                result.append(segment)
            }
        }
        return result
    }

    /// One "[HH:MM:SS] Io: text" line per segment (no label when the speaker is unknown).
    public static func render(_ segments: [TranscriptSegment]) -> String {
        segments.map { segment in
            let s = max(Int(segment.start), 0)
            let stamp = String(format: "[%02d:%02d:%02d] ", s / 3600, (s % 3600) / 60, s % 60)
            return stamp + (segment.speaker.map { $0.label + ": " } ?? "") + segment.text + "\n"
        }.joined()
    }

    public static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func hasSpeakers(_ text: String) -> Bool {
        text.contains("] Io: ") || text.contains("] Altri: ")
    }
}

public enum SiblingFiles {
    public static let tempSuffix = ".nastro-tmp"

    public static func transcriptURL(for recording: URL) -> URL {
        sibling(of: recording, suffix: ".trascrizione.txt")
    }

    public static func summaryURL(for recording: URL) -> URL {
        sibling(of: recording, suffix: ".riassunto.md")
    }

    public static func tempURL(for final: URL) -> URL {
        final.deletingLastPathComponent().appendingPathComponent(final.lastPathComponent + tempSuffix)
    }

    private static func sibling(of recording: URL, suffix: String) -> URL {
        recording.deletingLastPathComponent()
            .appendingPathComponent(recording.deletingPathExtension().lastPathComponent + suffix)
    }
}
