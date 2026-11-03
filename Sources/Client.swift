import Foundation

/// Minimal Yamaha Extended Control client. See doc/YXC_API_Spec_Basic_v2.0.pdf.
struct Client {
    enum Failure: LocalizedError {
        case badHost
        case device(Int)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .badHost: return "Invalid receiver address"
            case .device(let code): return "Receiver returned error \(code)"
            case .emptyResponse: return "Receiver sent an empty response"
            }
        }
    }

    let host: String

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        return URLSession(configuration: config)
    }()

    var baseURL: URL? { URL(string: "http://\(host)") }

    /// The receiver occasionally answers with an empty body, so retry once.
    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        do {
            return try await request(path)
        } catch Failure.emptyResponse {
            try await Task.sleep(nanoseconds: 200_000_000)
            return try await request(path)
        }
    }

    func send(_ path: String) async throws {
        let _: Ack = try await get(path)
    }

    func post<Body: Encodable>(_ path: String, body: Body) async throws {
        let _: Ack = try await request(path, body: JSONEncoder().encode(body))
    }

    private func request<T: Decodable>(_ path: String, body: Data? = nil) async throws -> T {
        guard let url = URL(string: "http://\(host)/YamahaExtendedControl/v1/\(path)") else {
            throw Failure.badHost
        }
        var request = URLRequest(url: url)
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
        }
        let (data, _) = try await Client.session.data(for: request)
        guard !data.isEmpty else { throw Failure.emptyResponse }
        let ack = try JSONDecoder().decode(Ack.self, from: data)
        guard ack.response_code == 0 else { throw Failure.device(ack.response_code) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct AppError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

struct Ack: Decodable {
    let response_code: Int
}

struct NetworkStatus: Decodable {
    let network_name: String
}

struct ZoneStatus: Decodable {
    let power: String
    let volume: Int
    let max_volume: Int?
    let mute: Bool
    let input: String
}

struct Features: Decodable {
    struct System: Decodable {
        struct Input: Decodable {
            let id: String
            let play_info_type: String?
        }
        let input_list: [Input]
    }
    struct Zone: Decodable {
        let id: String
        let input_list: [String]?
    }
    let system: System
    let zone: [Zone]
}

struct NameText: Decodable {
    struct Item: Decodable {
        let id: String
        let text: String
    }
    let input_list: [Item]?
}

struct NetPresets: Decodable {
    struct Item: Decodable {
        let input: String
        let text: String
    }
    let preset_info: [Item]
}

struct TunerPresets: Decodable {
    struct Item: Decodable {
        let band: String
        let number: Int
    }
    let preset_info: [Item]
}

struct PlayInfo: Decodable {
    let playback: String?
    let artist: String?
    let album: String?
    let track: String?
    let albumart_url: String?
}

struct TunerPlayInfo: Decodable {
    struct Band: Decodable {
        let freq: Int
    }
    let band: String
    let fm: Band?
    let am: Band?
}
