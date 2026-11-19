import Foundation
import NastroCore

public protocol ChatClient: Sendable {
    func complete(_ messages: [ChatMessage]) async throws -> String
}

/// Non-streaming client for OpenAI-compatible `/chat/completions` servers.
public struct OpenAIChatClient: ChatClient {
    private let settings: SummarySettings
    private let apiKey: String
    private let session: URLSession

    public init(settings: SummarySettings, apiKey: String, session: URLSession = .shared) {
        self.settings = settings
        self.apiKey = apiKey
        self.session = session
    }

    private struct RequestBody: Encodable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
        let temperature: Double
    }

    private struct Reply: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message?
        }
        let choices: [Choice]?
    }

    public func complete(_ messages: [ChatMessage]) async throws -> String {
        guard let url = settings.chatCompletionsURL else { throw SummaryError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 900
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(
            RequestBody(model: settings.model, messages: messages, stream: false, temperature: 0.3))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw SummaryError.modelUnreachable(url: settings.baseURL)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(decoding: data, as: UTF8.self)
            throw SummaryError.http(status: http.statusCode, detail: String(text.prefix(400)))
        }
        let content = (try? JSONDecoder().decode(Reply.self, from: data))?.choices?.first?.message?.content ?? ""
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SummaryError.emptyReply }
        return content
    }
}
