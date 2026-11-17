/// The kind of sample a capture pipeline produces.
public enum SampleKind: Sendable {
    case video, systemAudio, microphone
}

/// Video capture geometry and frame rate.
public struct VideoSpec: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let fps: Int

    public init(width: Int, height: Int, fps: Int) {
        self.width = width
        self.height = height
        self.fps = fps
    }
}
