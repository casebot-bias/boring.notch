import XCTest

/// Answers every request with a canned status and body, and records the last request and its body.
/// Never touches the network.
final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    static var lastRequest: URLRequest?
    static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lastRequest = request
        StubURLProtocol.lastBody = request.httpBody ?? Self.drain(request.httpBodyStream)

        let (status, body) = StubURLProtocol.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession hands a POST body to a URLProtocol as a stream rather than as `httpBody`.
    private static func drain(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let chunkSize = 1024
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while true {
            let read = stream.read(&buffer, maxLength: chunkSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

final class FleetClientTests: XCTestCase {

    /// Builds a client whose requests go through `StubURLProtocol` with the given handler.
    private func makeClient(handler: @escaping (URLRequest) -> (Int, Data)) -> FleetClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = handler
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastBody = nil
        return FleetClient(
            baseURL: URL(string: "https://fleet.example")!,
            session: URLSession(configuration: config)
        )
    }

    func testSendDecisionPostsTheContractRequest() async throws {
        let client = makeClient { _ in
            (200, Data(#"{"ok":true,"job":"ciri-skill-trim","option":"trim","action":"followup"}"#.utf8))
        }

        let answer = try await client.sendDecision(job: "ciri-skill-trim", option: "trim")

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/odin/decision")
        XCTAssertEqual(request.url?.host, "fleet.example")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fleet-Client"), "notch")
        XCTAssertGreaterThanOrEqual(StubURLProtocol.lastRequest?.timeoutInterval ?? 0, 60,
                                    "the answer may run a 60 s server-side command")

        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        let decoded = try JSONDecoder().decode([String: String].self, from: body)
        XCTAssertEqual(decoded, ["job": "ciri-skill-trim", "option": "trim"])

        XCTAssertTrue(answer.ok)
        XCTAssertEqual(answer.action, "followup")
    }

    func testSendDecisionThrowsTheServersMessageOnRejection() async throws {
        let client = makeClient { _ in
            (409, Data(#"{"ok":false,"error":"job still running"}"#.utf8))
        }

        do {
            _ = try await client.sendDecision(job: "ciri-skill-trim", option: "trim")
            XCTFail("expected a rejection")
        } catch let error as FleetClientError {
            XCTAssertEqual(error, .decisionRejected(409, "job still running"))
        }
    }

    func testSendDecisionToleratesAnEmptyErrorBody() async throws {
        let client = makeClient { _ in (500, Data()) }

        do {
            _ = try await client.sendDecision(job: "ciri-skill-trim", option: "trim")
            XCTFail("expected a rejection")
        } catch let error as FleetClientError {
            XCTAssertEqual(error, .decisionRejected(500, nil))
        }
    }
}
