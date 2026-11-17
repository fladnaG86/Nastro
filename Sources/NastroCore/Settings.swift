import Foundation

public enum RecordingMode: String, Codable, Sendable { case videoAndAudio, audioOnly }

public enum VideoSource: Codable, Hashable, Sendable {
    case mainDisplay, display(id: UInt32), window(id: UInt32)
}

public struct Settings: Codable, Equatable, Sendable {
    public var mode: RecordingMode
    public var videoSource: VideoSource
    public var systemAudio: Bool
    public var microphone: Bool
    /// nil = system default input.
    public var microphoneID: String?
    public var outputFolder: URL
    public var maxLongSide: Int
    public var fps: Int
    public var keepSeparateTracks: Bool
    public var hotKeyLetter: String

    /// Letters reserved by another app; the hotkey may never use them.
    static let reservedLetters: Set<String> = ["S", "R", "T"]

    public static let `default` = Settings(
        mode: .videoAndAudio,
        videoSource: .mainDisplay,
        systemAudio: true,
        microphone: true,
        microphoneID: nil,
        outputFolder: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("Nastro", isDirectory: true),
        maxLongSide: 1920,
        fps: 30,
        keepSeparateTracks: false,
        hotKeyLetter: "N"
    )

    public func validated() -> Settings {
        var s = self
        s.fps = min(max(fps, 5), 60)
        s.maxLongSide = min(max(maxLongSide, 640), 3840)
        if s.mode == .audioOnly, !s.systemAudio, !s.microphone { s.systemAudio = true }
        let letter = hotKeyLetter.uppercased()
        let isLetter = letter.count == 1 && letter.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) }
        s.hotKeyLetter = (isLetter && !Settings.reservedLetters.contains(letter)) ? letter : "N"
        return s
    }
}

public final class SettingsStore {
    private let defaults: UserDefaults
    private static let key = "settings"

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func load() -> Settings {
        guard let data = defaults.data(forKey: Self.key),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings.default.validated() }
        return s.validated()
    }

    public func save(_ s: Settings) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
