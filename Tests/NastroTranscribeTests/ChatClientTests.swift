import XCTest
import NastroCore
@testable import NastroTranscribe

/// URLProtocol stub. State is keyed by a per-test id sent as a session-level header,
/// so tests can run in parallel without sharing mutable state.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    enum Outcome { case response(status: Int, body: Data), failure(URLError) }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var outcomes: [String: Outcome] = [:]
    nonisolated(unsafe) private static var captured: [String: URLRequest] = [:]
    nonisolated(unsafe) private static var bodies: [String: Data] = [:]
    static let header = "X-Stub-ID"

    static func session(_ outcome: Outcome) -> (URLSession, String) {
        let id = UUID().uuidString
        lock.lock(); outcomes[id] = outcome; lock.unlock()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        config.httpAdditionalHeaders = [header: id]
        return (URLSession(configuration: config), id)
    }

    static func request(_ id: String) -> URLRequest? { lock.lock(); defer { lock.unlock() }; return captured[id] }
    static func body(_ id: String) -> Data? { lock.lock(); defer { lock.unlock() }; return bodies[id] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: Self.header) ?? ""
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            body = data
        }
        Self.lock.lock()
        Self.captured[id] = request
        Self.bodies[id] = body
        let outcome = Self.outcomes[id]
        Self.lock.unlock()
        switch outcome {
        case .response(let status, let data):
            let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
        }
    }
    override func stopLoading() {}
}

final class ChatClientTests: XCTestCase {
    private let messages = [ChatMessage(role: "system", content: "sys"), ChatMessage(role: "user", content: "ciao")]

    private func ok(_ content: String) -> StubProtocol.Outcome {
        let json = try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
        return .response(status: 200, body: json)
    }

    func testSendsModelMessagesAndParsesContent() async throws {
        let (session, id) = StubProtocol.session(ok("## Decisioni\nNessuna"))
        let client = OpenAIChatClient(settings: .default, apiKey: "", session: session)
        let result = try await client.complete(messages)
        XCTAssertEqual(result, "## Decisioni\nNessuna")
        let req = try XCTUnwrap(StubProtocol.request(id))
        XCTAssertEqual(req.url?.absoluteString, "http://127.0.0.1:8001/v1/chat/completions")
        XCTAssertEqual(req.httpMethod, "POST")
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(StubProtocol.body(id))) as? [String: Any])
        XCTAssertEqual(obj["model"] as? String, "gemma-4-26b-a4b")
        XCTAssertEqual(obj["stream"] as? Bool, false)
        XCTAssertEqual(obj["temperature"] as? Double, 0.3)
        let msgs = try XCTUnwrap(obj["messages"] as? [[String: String]])
        XCTAssertEqual(msgs, [["role": "system", "content": "sys"], ["role": "user", "content": "ciao"]])
    }

    func testBearerOnlyWithKey() async throws {
        let (s1, id1) = StubProtocol.session(ok("x"))
        _ = try await OpenAIChatClient(settings: .default, apiKey: "", session: s1).complete(messages)
        XCTAssertNil(StubProtocol.request(id1)?.value(forHTTPHeaderField: "Authorization"))
        let (s2, id2) = StubProtocol.session(ok("x"))
        _ = try await OpenAIChatClient(settings: .default, apiKey: "k", session: s2).complete(messages)
        XCTAssertEqual(StubProtocol.request(id2)?.value(forHTTPHeaderField: "Authorization"), "Bearer k")
    }

    func testHTTPErrorCarriesStatusAndFirst400Chars() async {
        let (session, _) = StubProtocol.session(.response(status: 500, body: Data(String(repeating: "e", count: 1000).utf8)))
        let client = OpenAIChatClient(settings: .default, apiKey: "", session: session)
        do {
            _ = try await client.complete(messages)
            XCTFail("expected error")
        } catch let SummaryError.http(status, detail) {
            XCTAssertEqual(status, 500)
            XCTAssertEqual(detail.count, 400)
        } catch { XCTFail("wrong error \(error)") }
    }

    func testConnectionRefusedIsUnreachable() async {
        for code in [URLError.Code.cannotConnectToHost, .timedOut] {
            let (session, _) = StubProtocol.session(.failure(URLError(code)))
            let client = OpenAIChatClient(settings: .default, apiKey: "", session: session)
            do {
                _ = try await client.complete(messages)
                XCTFail("expected error")
            } catch {
                XCTAssertEqual(error as? SummaryError, .modelUnreachable(url: "http://127.0.0.1:8001/v1"))
            }
        }
    }

    func testCancelledURLErrorPropagatesAsCancellation() async {
        let (session, _) = StubProtocol.session(.failure(URLError(.cancelled)))
        let client = OpenAIChatClient(settings: .default, apiKey: "", session: session)
        do {
            _ = try await client.complete(messages)
            XCTFail("expected error")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testEmptyContentIsEmptyReply() async {
        let (session, _) = StubProtocol.session(ok("  "))
        let client = OpenAIChatClient(settings: .default, apiKey: "", session: session)
        do {
            _ = try await client.complete(messages)
            XCTFail("expected error")
        } catch { XCTAssertEqual(error as? SummaryError, .emptyReply) }
    }

    func testMissingChoicesIsEmptyReply() async {
        let (session, _) = StubProtocol.session(.response(status: 200, body: Data("{}".utf8)))
        let client = OpenAIChatClient(settings: .default, apiKey: "", session: session)
        do {
            _ = try await client.complete(messages)
            XCTFail("expected error")
        } catch { XCTAssertEqual(error as? SummaryError, .emptyReply) }
    }

    func testInvalidBaseURL() async {
        let client = OpenAIChatClient(settings: SummarySettings(baseURL: "not a url", model: "m"), apiKey: "")
        do {
            _ = try await client.complete(messages)
            XCTFail("expected error")
        } catch { XCTAssertEqual(error as? SummaryError, .invalidURL) }
    }
}
