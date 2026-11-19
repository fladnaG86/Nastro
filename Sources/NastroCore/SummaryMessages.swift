import Foundation

/// User-facing texts for the transcription/summary job: error messages for notifications and
/// the phase shown in the menu.
public enum SummaryMessages {
    /// nil for `.cancelled`: the user asked for it, nothing to notify.
    public static func text(_ error: SummaryError, language: L10n.Language = .current) -> String? {
        func t(_ key: L10n.Key) -> String { L10n.t(key, language: language) }
        switch error {
        case .noAudio: return t(.errNoAudio)
        case .noSpeech: return t(.errNoSpeech)
        case .speechModelUnavailable: return t(.errSpeechModel)
        case .cannotWrite: return t(.errCannotWrite)
        case .invalidURL: return t(.errInvalidURL)
        case .modelUnreachable(let url): return String(format: t(.errUnreachable), url)
        case .http(let status, let detail):
            // Status 0 = an error outside the chat client's contract: there is no HTTP status to show.
            if status > 0 { return String(format: t(.errHTTP), status, detail) }
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? t(.errServer) : trimmed
        case .emptyReply: return t(.errEmptyReply)
        case .cancelled: return nil
        }
    }

    public static func phaseText(_ phase: SummaryPhase, language: L10n.Language = .current) -> String {
        switch phase {
        case .preparing:
            return L10n.t(.summaryPreparing, language: language)
        case .transcribing(let fraction):
            let safe = fraction.isFinite ? min(max(fraction, 0), 1) : 0
            let percent = Int((safe * 100).rounded())
            return String(format: L10n.t(.summaryTranscribing, language: language), percent)
        case .summarizing(let part, let total):
            if total <= 1 { return L10n.t(.summarySummarizingOne, language: language) }
            return String(format: L10n.t(.summarySummarizing, language: language), part, total)
        }
    }
}
