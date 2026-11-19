import Foundation
import NastroCore

/// Splits one recognizer result into sentence-level segments from its timed words, so that
/// two speakers' lines interleave correctly after `Transcript.merge`.
enum SentenceSplitter {
    struct Word: Equatable {
        var text: String
        var start: Double?
        var end: Double?
    }

    static let pause: Double = 1.0
    private static let sentenceEnds: [Character] = [".", "?", "!", "…"]

    /// A segment closes after a word ending in `.`, `?`, `!` or `…`, or before a pause of at least
    /// `pause` seconds; leftovers close at the end. Missing word times fall back to `range`.
    static func split(_ words: [Word], range: (start: Double, end: Double), speaker: Speaker?) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var buffer: [Word] = []

        func flush() {
            defer { buffer.removeAll() }
            let text = buffer.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let start = buffer.lazy.compactMap(\.start).first ?? range.start
            let end = buffer.reversed().lazy.compactMap(\.end).first ?? range.end
            segments.append(TranscriptSegment(start: start, end: max(end, start), text: text, speaker: speaker))
        }

        for (index, word) in words.enumerated() {
            buffer.append(word)
            let trimmed = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let endsSentence = trimmed.last.map { sentenceEnds.contains($0) } ?? false
            var pauseFollows = false
            if let end = word.end, index + 1 < words.count, let next = words[index + 1].start {
                pauseFollows = next - end >= pause
            }
            if endsSentence || pauseFollows { flush() }
        }
        flush()
        return segments
    }
}
