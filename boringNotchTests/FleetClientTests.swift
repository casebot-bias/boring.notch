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

    func testFetchJobsDecodesTheFeed() async throws {
        let client = makeClient { _ in
            (200, Data(#"{"generatedAt":"x","jobs":[{"job":"a","running":true,"itemsPassed":1,"itemsTotal":3}]}"#.utf8))
        }
        let snapshot = try await client.fetchJobs()
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/api/jobs")
        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(snapshot?.jobs.map(\.job), ["a"])
        XCTAssertEqual(snapshot?.jobs.first?.itemsTotal, 3)
    }

    func testFetchJobsOn404IsNilSoAnOldDashboardLeavesThePanelAlone() async throws {
        let client = makeClient { _ in (404, Data("Not Found".utf8)) }
        let snapshot = try await client.fetchJobs()
        XCTAssertNil(snapshot)
    }

    func testFetchJobsThrowsOnOtherFailures() async throws {
        let client = makeClient { _ in (500, Data()) }
        do {
            _ = try await client.fetchJobs()
            XCTFail("expected a failure")
        } catch let error as FleetClientError {
            XCTAssertEqual(error, .badStatus(500))
        }
        let garbled = makeClient { _ in (200, Data("not json".utf8)) }
        do {
            _ = try await garbled.fetchJobs()
            XCTFail("expected a decoding failure")
        } catch let error as FleetClientError {
            guard case .decoding = error else { return XCTFail("expected decoding, got \(error)") }
        }
    }

    /// A decision's own `rerun` option reaches the notch's list and goes back to the API as its id.
    func testRerunOptionRoundTripsFromTheFeedToTheRequest() async throws {
        let json = """
        {"generatedAt":"x","devices":[{"device":"odin","items":[],"state":"ok","odin":{"open":[
          {"state":"needs_decision","job":"notch-job-heartbeat","pr":9,"reason":"qa_skipped",
           "options":[{"id":"rerun","label":"Run the review again","pick":true},
                      {"id":"stop","label":"Stop, close the PR","pick":false}]}]}}]}
        """
        let activity = try ActivitySnapshot.decode(Data(json.utf8))
        let model = FleetPanelModelBuilder.build(fleet: nil, activity: activity, fleetLive: false)
        let decision = try XCTUnwrap(model.decisions.first)
        XCTAssertEqual(decision.reason, "qa_skipped")
        XCTAssertEqual(decision.options.map(\.id), ["rerun", "stop"], "the decision's own options, not the defaults")
        let option = try XCTUnwrap(decision.options.first { $0.id == "rerun" })
        XCTAssertEqual(option.label, "Run the review again")

        let client = makeClient { _ in (200, Data(#"{"ok":true,"action":"followup"}"#.utf8)) }
        _ = try await client.sendDecision(job: try XCTUnwrap(decision.job), option: option.id)
        let body = try XCTUnwrap(StubURLProtocol.lastBody)
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: body),
                       ["job": "notch-job-heartbeat", "option": "rerun"])
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
