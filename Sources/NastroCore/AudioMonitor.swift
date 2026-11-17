import Foundation

public enum AudioLevel {
    public static let floorDB: Float = -100

    /// Peak absolute sample value in dBFS; `floorDB` for an empty or all-zero buffer.
    public static func peakDB(_ samples: UnsafeBufferPointer<Float>) -> Float {
        var peak: Float = 0
        for s in samples { peak = max(peak, abs(s)) }
        guard peak > 0 else { return floorDB }
        return max(20 * log10(peak), floorDB)
    }
}

public struct SilenceDetector: Sendable {
    public let thresholdDB: Float
    public let grace: TimeInterval
    private var startedAt: TimeInterval = 0
    private var lastLoudAt: TimeInterval?

    public init(thresholdDB: Float = -60, grace: TimeInterval = 5) {
        self.thresholdDB = thresholdDB
        self.grace = grace
    }

    public mutating func start(at t: TimeInterval) {
        startedAt = t
        lastLoudAt = nil
    }

    public mutating func feed(levelDB: Float, at t: TimeInterval) {
        if levelDB > thresholdDB { lastLoudAt = t }
    }

    public func isSilent(at t: TimeInterval) -> Bool {
        let reference = max(startedAt, lastLoudAt ?? startedAt)
        return t - reference >= grace
    }
}

public enum DiskGuard {
    public static let minimumFreeBytes: Int64 = 1_000_000_000
    public static func shouldStop(freeBytes: Int64) -> Bool { freeBytes < minimumFreeBytes }
}
