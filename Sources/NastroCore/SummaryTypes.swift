import Foundation

public enum SummaryError: Error, Equatable, Sendable {
    case noAudio
    case noSpeech
    case speechModelUnavailable
    case cannotWrite
    case invalidURL
    case modelUnreachable(url: String)
    case http(status: Int, detail: String)
    case emptyReply
    case cancelled
}

public enum SummaryPhase: Sendable, Equatable {
    case preparing
    case transcribing(Double)
    case summarizing(part: Int, of: Int)
}
