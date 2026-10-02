import Foundation

enum FleetClientError: Error, Equatable {
    case badStatus(Int)
    case transport(String)
    case decoding(String)
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
