import Foundation

actor Neo4jQueryClient {
    private let endpoint: URL?
    private let username: String
    private let password: String
    private let session: URLSession
    private var bookmarks: [String] = []

    init(
        host: String,
        database: String,
        username: String,
        password: String,
        session: URLSession = .shared
    ) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/db/\(database)/query/v2"
        endpoint = host.hasSuffix(".databases.neo4j.io") ? components.url : nil
        self.username = username
        self.password = password
        self.session = session
    }

    func checkConnection() async throws {
        _ = try await run(statement: "RETURN 'ok' AS status")
    }

    func recordObservation(_ memory: MemoryItem) async throws {
        let statement = """
        MERGE (o:Object {id: $objectId})
        MERGE (p:Place {id: $placeId})
        MERGE (obs:Observation {id: $observationId})
        ON CREATE SET obs.seenAt = datetime($seenAt), obs.evidenceId = $evidenceId, obs.summary = $summary
        MERGE (obs)-[:OF]->(o)
        MERGE (obs)-[:AT]->(p)
        RETURN o.id AS objectId, p.id AS placeId, obs.id AS observationId
        """

        _ = try await run(
            statement: statement,
            parameters: [
                "objectId": memory.title.normalizedGraphID,
                "placeId": memory.place.normalizedGraphID,
                "observationId": memory.id.uuidString,
                "seenAt": ISO8601DateFormatter().string(from: memory.capturedAt),
                "evidenceId": memory.id.uuidString,
                "summary": memory.summary
            ]
        )
    }

    @discardableResult
    func run(statement: String, parameters: [String: String] = [:]) async throws -> Neo4jQueryResponse {
        guard let endpoint, !username.isEmpty, !password.isEmpty else {
            throw ServiceError.notConfigured("Neo4j Aura")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let credential = Data("\(username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(credential)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            Neo4jQueryBody(
                statement: statement,
                parameters: parameters,
                bookmarks: bookmarks.isEmpty ? nil : bookmarks
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw ServiceError.http(
                service: "Neo4j",
                status: http.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }

        let result = try JSONDecoder().decode(Neo4jQueryResponse.self, from: data)
        if let first = result.errors?.first {
            throw ServiceError.http(service: "Neo4j", status: http.statusCode, message: first.message)
        }
        bookmarks = result.bookmarks ?? bookmarks
        return result
    }
}

private struct Neo4jQueryBody: Encodable {
    let statement: String
    let parameters: [String: String]
    let bookmarks: [String]?
}

struct Neo4jQueryResponse: Decodable, Sendable {
    struct QueryError: Decodable, Sendable {
        let code: String
        let message: String
    }

    struct DataRows: Decodable, Sendable {
        let fields: [String]
        let values: [[JSONValue]]
    }

    let data: DataRows?
    let errors: [QueryError]?
    let bookmarks: [String]?
}

enum JSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

private extension String {
    var normalizedGraphID: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let transformed = lowercased().unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        return String(transformed).replacingOccurrences(of: "--", with: "-")
    }
}
