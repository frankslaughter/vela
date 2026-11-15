import Foundation

/// What the base station hands back when a phone asks to join.
struct JoinTicket: Decodable {
    let boat: String
    let assistant: String
    let channels: [String]
    let channel: String
    let identity: String
    let name: String
    let livekitURL: String
    let token: String

    enum CodingKeys: String, CodingKey {
        case boat, assistant, channels, channel, identity, name, token
        case livekitURL = "livekit_url"
    }
}

struct ControlError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Talks to the control service on the base station.
enum ControlClient {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func join(boat: Boat, deviceID: String, name: String, channel: String?) async throws -> JoinTicket {
        guard let url = boat.baseURL?.appending(path: "api/join") else {
            throw ControlError(message: "The base station advertised an address the app cannot use.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: String] = ["device_id": deviceID, "name": name]
        if let channel { body["channel"] = channel }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ControlError(message: "The base station gave no usable answer.")
        }
        guard http.statusCode == 200 else {
            let detail = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"]
            throw ControlError(message: detail ?? "The base station refused the join (\(http.statusCode)).")
        }
        return try JSONDecoder().decode(JoinTicket.self, from: data)
    }
}
