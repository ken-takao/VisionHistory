import Foundation

actor FileVectorMemoryStore: VectorMemoryStore {
    private let fileURL: URL
    private var memories: [MemoryItem] = []
    private var didLoad = false

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base.appending(path: "KIOKURelay", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "memories.json")
    }

    func loadAll() async throws -> [MemoryItem] {
        try loadIfNeeded()
        return memories.sorted { $0.capturedAt > $1.capturedAt }
    }

    func upsert(_ memory: MemoryItem) async throws {
        try loadIfNeeded()
        if let index = memories.firstIndex(where: { $0.id == memory.id }) {
            memories[index] = memory
        } else {
            memories.append(memory)
        }
        try persist()
    }

    func markNeo4jSynced(id: UUID) async throws {
        try loadIfNeeded()
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return }
        memories[index].neo4jSynced = true
        try persist()
    }

    func search(text: String, textEmbedding: [Float], limit: Int = 20) async throws -> [ScoredMemory] {
        try loadIfNeeded()
        let normalizedQuery = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let queryTerms = Set(normalizedQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init))

        return memories
            .map { memory in
                let haystack = ([memory.title, memory.summary, memory.place] + memory.tags)
                    .joined(separator: " ")
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

                let lexical: Double
                if normalizedQuery.isEmpty {
                    lexical = 0.5
                } else if haystack.contains(normalizedQuery) {
                    lexical = 1
                } else {
                    let hits = queryTerms.filter { haystack.contains($0) }.count
                    lexical = queryTerms.isEmpty ? 0 : Double(hits) / Double(queryTerms.count)
                }

                let semantic = VectorMath.cosine(textEmbedding, memory.textEmbedding)
                let recency = max(0, 1 - Date.now.timeIntervalSince(memory.capturedAt) / (86_400 * 30))
                return ScoredMemory(
                    memory: memory,
                    score: lexical * 0.56 + max(semantic, 0) * 0.36 + recency * 0.08
                )
            }
            .filter { normalizedQuery.isEmpty || $0.score > 0.08 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    func searchSimilar(visualEmbedding: [Float], limit: Int = 10) async throws -> [ScoredMemory] {
        try loadIfNeeded()
        return memories
            .filter { !$0.visualEmbedding.isEmpty }
            .map { ScoredMemory(memory: $0, score: VectorMath.cosine(visualEmbedding, $0.visualEmbedding)) }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    private func loadIfNeeded() throws {
        guard !didLoad else { return }
        defer { didLoad = true }

        guard FileManager.default.fileExists(atPath: fileURL.path()) else {
            memories = MemoryItem.demoItems
            try persist()
            return
        }

        let data = try Data(contentsOf: fileURL)
        memories = try JSONDecoder.storage.decode([MemoryItem].self, from: data)
    }

    private func persist() throws {
        let data = try JSONEncoder.storage.encode(memories)
        try data.write(to: fileURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var storage: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var storage: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
