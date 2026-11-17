import Foundation

public enum StopReason: Equatable, Sendable { case user, sourceLost, streamError, diskFull }

public enum RecorderState: Equatable, Sendable {
    case idle, starting, recording(since: Date), finalizing(reason: StopReason)
}

public enum RecorderEvent: Equatable, Sendable {
    case startRequested, started(at: Date), startFailed
    case stopRequested(StopReason), finalized, finalizeFailed
}

public struct RecorderMachine: Sendable {
    public private(set) var state: RecorderState = .idle

    public init() {}

    /// Returns false (and leaves the state untouched) when the event is not valid in the current state.
    public mutating func apply(_ event: RecorderEvent) -> Bool {
        switch (state, event) {
        case (.idle, .startRequested): state = .starting
        case (.starting, .started(let t)): state = .recording(since: t)
        case (.starting, .startFailed): state = .idle
        case (.starting, .stopRequested(let r)), (.recording, .stopRequested(let r)): state = .finalizing(reason: r)
        case (.finalizing, .finalized), (.finalizing, .finalizeFailed): state = .idle
        default: return false
        }
        return true
    }
}
