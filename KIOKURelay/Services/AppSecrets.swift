import Foundation

struct AppSecrets: Sendable {
    let environment: String
    let openAIAPIKey: String
    let shisaAPIKey: String
    let neo4jHost: String
    let neo4jUsername: String
    let neo4jPassword: String
    let neo4jDatabase: String

    init(bundle: Bundle = .main) {
        func value(_ key: String) -> String {
            let raw = bundle.object(forInfoDictionaryKey: key) as? String ?? ""
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        environment = value("AppEnvironment")
        openAIAPIKey = value("OpenAIAPIKey")
        shisaAPIKey = value("ShisaAPIKey")
        neo4jHost = value("Neo4jHost")
            .replacingOccurrences(of: "neo4j+s://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        neo4jUsername = value("Neo4jUsername")
        neo4jPassword = value("Neo4jPassword")
        neo4jDatabase = value("Neo4jDatabase").isEmpty ? "neo4j" : value("Neo4jDatabase")
    }

    var hasOpenAI: Bool { openAIAPIKey.hasPrefix("sk-") }
    var hasShisa: Bool { shisaAPIKey.hasPrefix("shsk:") }
    var hasNeo4j: Bool {
        neo4jHost.hasSuffix(".databases.neo4j.io")
            && !neo4jUsername.isEmpty
            && !neo4jPassword.isEmpty
    }
}
