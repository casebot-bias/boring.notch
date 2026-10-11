import Foundation

enum FleetClientError: Error, Equatable {
    case badStatus(Int)
    case transport(String)
    case decoding(String)
    case decisionRejected(Int, String?)
}

/// The body of an owner's answer.
private struct DecisionRequest: Encodable {
    let job: String
    let option: String
}

/// The fleet API's answer to an owner decision.
struct DecisionAnswer: Decodable, Equatable {
    var ok: Bool
    var action: String?   // "followup" | "backlog" | "closed"

    private enum CodingKeys: String, CodingKey { case ok, action }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.ok = try container.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        self.action = try container.decodeIfPresent(String.self, forKey: .action)
    }
}

struct FleetClient {
    var baseURL: URL
    var session: URLSession = .shared
    var timeout: TimeInterval = 3

    func fetchFleet() async throws -> FleetSnapshot {
        let url = baseURL.appendingPathComponent("api/fleet")
        let (data, response) = try await request(url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FleetClientError.badStatus(0)
        }
        guard httpResponse.statusCode == 200 else {
            throw FleetClientError.badStatus(httpResponse.statusCode)
        }
        do {
            return try FleetSnapshot.decode(data)
        } catch {
            throw FleetClientError.decoding(error.localizedDescription)
        }
    }

    func fetchActivity() async throws -> ActivitySnapshot {
        let url = baseURL.appendingPathComponent("api/activity")
        let (data, response) = try await request(url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FleetClientError.badStatus(0)
        }
        guard httpResponse.statusCode == 200 else {
            throw FleetClientError.badStatus(httpResponse.statusCode)
        }
        do {
            return try ActivitySnapshot.decode(data)
        } catch {
            throw FleetClientError.decoding(error.localizedDescription)
        }
    }

    /// Answers one open Odin decision: `POST <base>/api/odin/decision` with the contract's JSON
    /// body and the notch's client header. 200 decodes the answer; every other status is a
    /// `decisionRejected` carrying the server's short message when it sent one.
    func sendDecision(job: String, option: String) async throws -> DecisionAnswer {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/odin/decision"),
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("notch", forHTTPHeaderField: "X-Fleet-Client")
        do {
            request.httpBody = try JSONEncoder().encode(DecisionRequest(job: job, option: option))
        } catch {
            throw FleetClientError.decoding(error.localizedDescription)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw FleetClientError.transport(error.localizedDescription)
        } catch {
            throw FleetClientError.transport(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FleetClientError.badStatus(0)
        }
        guard httpResponse.statusCode == 200 else {
            throw FleetClientError.decisionRejected(httpResponse.statusCode, Self.serverMessage(data))
        }
        do {
            return try JSONDecoder().decode(DecisionAnswer.self, from: data)
        } catch {
            throw FleetClientError.decoding(error.localizedDescription)
        }
    }

    /// The API's `{"ok":false,"error":"..."}` message, when the body carries one.
    private static func serverMessage(_ data: Data) -> String? {
        struct Body: Decodable { var error: String? }
        return (try? JSONDecoder().decode(Body.self, from: data))?.error
    }

    private func request(_ url: URL) async throws -> (Data, URLResponse) {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw FleetClientError.transport(error.localizedDescription)
        } catch {
            throw FleetClientError.transport(error.localizedDescription)
        }
    }
}
