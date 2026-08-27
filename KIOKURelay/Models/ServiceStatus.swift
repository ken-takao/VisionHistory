import Foundation

enum ServiceKind: String, CaseIterable, Identifiable, Sendable {
    case localAI = "Apple Local AI"
    case qdrant = "Qdrant Edge"
    case openAI = "OpenAI"
    case neo4j = "Neo4j Aura"
    case shisa = "Shisa Voice"

    var id: String { rawValue }
}

enum ConnectionState: Equatable, Sendable {
    case local
    case notConfigured
    case checking
    case connected
    case failed(String)
}

struct ServiceStatus: Identifiable, Sendable {
    let kind: ServiceKind
    var state: ConnectionState

    var id: ServiceKind { kind }
}
