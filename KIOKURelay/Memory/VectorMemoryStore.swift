import Foundation

struct ScoredMemory: Identifiable, Sendable {
    let memory: MemoryItem
    let score: Double

    var id: UUID { memory.id }
}

protocol VectorMemoryStore: Sendable {
    func loadAll() async throws -> [MemoryItem]
    func upsert(_ memory: MemoryItem) async throws
    func markNeo4jSynced(id: UUID) async throws
    func search(text: String, textEmbedding: [Float], limit: Int) async throws -> [ScoredMemory]
    func searchSimilar(visualEmbedding: [Float], limit: Int) async throws -> [ScoredMemory]
}
