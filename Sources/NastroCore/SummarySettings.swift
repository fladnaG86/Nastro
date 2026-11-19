import Foundation

public struct SummarySettings: Codable, Equatable, Sendable {
    public var baseURL: String
    public var model: String

    public init(baseURL: String, model: String) {
        self.baseURL = baseURL
        self.model = model
    }

    public static let `default` = SummarySettings(baseURL: "http://127.0.0.1:8001/v1", model: "gemma-4-26b-a4b")

    /// True when the server runs on this Mac (loopback host).
    public var isLocal: Bool {
        guard let host = chatCompletionsURL?.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    public var chatCompletionsURL: URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        let full = base.hasSuffix("/chat/completions") ? base : base + "/chat/completions"
        guard let url = URL(string: full),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    public func validated() -> SummarySettings {
        let b = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return SummarySettings(baseURL: b.isEmpty ? Self.default.baseURL : b,
                               model: m.isEmpty ? Self.default.model : m)
    }
}

/// Own UserDefaults key: kept out of `Settings` so old saved recording settings keep decoding.
public final class SummarySettingsStore {
    private let defaults: UserDefaults
    private static let key = "summarySettings"

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func load() -> SummarySettings {
        guard let data = defaults.data(forKey: Self.key),
              let s = try? JSONDecoder().decode(SummarySettings.self, from: data) else { return SummarySettings.default.validated() }
        return s.validated()
    }

    public func save(_ s: SummarySettings) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
