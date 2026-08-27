#if canImport(EdgeBridge)
import Foundation

/// Keeps complete `MemoryItem` values in the existing JSON store and uses
/// Qdrant Edge only as the on-device visual-vector index.
actor QdrantVectorMemoryStore: VectorMemoryStore {
    // Vision feature-print revision 2 currently produces 768 values. Existing
    // stored vectors take precedence so a future model dimension is detected.
    private static let defaultVisualDimension = 768
    private static let upsertBatchSize = 500

    private let metadataStore: any VectorMemoryStore
    private let shardURL: URL
    private let bridgeFactory: @Sendable (Data) throws -> any QdrantEdgeSession
    private var bridge: (any QdrantEdgeSession)?
    private var vectorDimension: Int?
    private var didBackfill = false
    private var isBridgeDisabled = false

    init() {
        let fileManager = FileManager.default
        metadataStore = FileVectorMemoryStore()
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        shardURL = base
            .appending(path: "KIOKURelay", directoryHint: .isDirectory)
            .appending(path: "qdrant-visual", directoryHint: .isDirectory)
        bridgeFactory = { try LiveQdrantEdgeSession(createJSON: $0) }
    }

    init(
        metadataStore: any VectorMemoryStore,
        shardURL: URL,
        bridgeFactory: @escaping @Sendable (Data) throws -> any QdrantEdgeSession
    ) {
        self.metadataStore = metadataStore
        self.shardURL = shardURL
        self.bridgeFactory = bridgeFactory
    }

    func loadAll() async throws -> [MemoryItem] {
        let memories = try await metadataStore.loadAll()
        guard !isBridgeDisabled else { return memories }
        let dimension = memories.first(where: { !$0.visualEmbedding.isEmpty })?
            .visualEmbedding.count ?? Self.defaultVisualDimension
        do {
            try ensureBridge(vectorDimension: dimension)
            try backfillIfNeeded(memories)
        } catch {
            disableBridge()
        }
        return memories
    }

    func upsert(_ memory: MemoryItem) async throws {
        // The JSON store is authoritative. A later launch can rebuild Qdrant
        // if vector indexing is interrupted after this durable write.
        try await metadataStore.upsert(memory)
        guard !memory.visualEmbedding.isEmpty, !isBridgeDisabled else { return }
        do {
            try ensureBridge(vectorDimension: memory.visualEmbedding.count)
            try upsertVisualMemories([memory])
            try flushBridge()
        } catch {
            // Metadata is already durable. Disable the optional index for the
            // rest of this actor session and rebuild it on a future launch.
            disableBridge()
        }
    }

    func markNeo4jSynced(id: UUID) async throws {
        try await metadataStore.markNeo4jSynced(id: id)
    }

    func search(
        text: String,
        textEmbedding: [Float],
        limit: Int
    ) async throws -> [ScoredMemory] {
        try await metadataStore.search(text: text, textEmbedding: textEmbedding, limit: limit)
    }

    func searchSimilar(
        visualEmbedding: [Float],
        limit: Int
    ) async throws -> [ScoredMemory] {
        guard !visualEmbedding.isEmpty, limit > 0 else { return [] }

        let memories = try await metadataStore.loadAll()
        guard !isBridgeDisabled else {
            return try await metadataStore.searchSimilar(
                visualEmbedding: visualEmbedding,
                limit: limit
            )
        }

        do {
            try ensureBridge(vectorDimension: visualEmbedding.count)
            try backfillIfNeeded(memories)

            let request = QueryRequest(
                vector: visualEmbedding,
                limit: min(limit, 1_000),
                withPayload: true,
                withVector: false
            )
            let responseData = try requiredBridge().query(json: try Self.encode(request))
            let response = try JSONDecoder().decode(QueryResponse.self, from: responseData)
            let memoriesByID = Dictionary(uniqueKeysWithValues: memories.map { ($0.id, $0) })

            return response.hits.compactMap { hit in
                guard let id = hit.id.uuid, let memory = memoriesByID[id] else { return nil }
                return ScoredMemory(memory: memory, score: hit.score)
            }
        } catch {
            disableBridge()
            return try await metadataStore.searchSimilar(
                visualEmbedding: visualEmbedding,
                limit: limit
            )
        }
    }

    private func ensureBridge(vectorDimension requestedDimension: Int) throws {
        guard !isBridgeDisabled else {
            throw QdrantVectorMemoryStoreError.bridgeDisabled
        }
        guard requestedDimension > 0 else {
            throw QdrantVectorMemoryStoreError.invalidVectorDimension(requestedDimension)
        }
        if let vectorDimension, vectorDimension != requestedDimension {
            throw QdrantVectorMemoryStoreError.vectorDimensionMismatch(
                expected: vectorDimension,
                actual: requestedDimension
            )
        }
        guard bridge == nil else { return }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: shardURL, withIntermediateDirectories: true)
        let configURL = shardURL.appending(path: "edge_config.json")
        let request = CreateRequest(
            path: shardURL.path(percentEncoded: false),
            vectorSize: requestedDimension,
            distance: "cosine",
            onDiskPayload: false,
            onDiskVectors: false,
            openExisting: fileManager.fileExists(atPath: configURL.path(percentEncoded: false)),
            maxSearchThreads: 2
        )
        bridge = try bridgeFactory(Self.encode(request))
        vectorDimension = requestedDimension
    }

    private func backfillIfNeeded(_ memories: [MemoryItem]) throws {
        guard !didBackfill else { return }
        let indexed = memories.filter { !$0.visualEmbedding.isEmpty }
        if !indexed.isEmpty {
            try upsertVisualMemories(indexed)
            try flushBridge()
        }
        didBackfill = true
    }

    private func upsertVisualMemories(_ memories: [MemoryItem]) throws {
        guard let vectorDimension else {
            throw QdrantVectorMemoryStoreError.bridgeNotInitialized
        }
        for memory in memories where memory.visualEmbedding.count != vectorDimension {
            throw QdrantVectorMemoryStoreError.vectorDimensionMismatch(
                expected: vectorDimension,
                actual: memory.visualEmbedding.count
            )
        }

        for start in stride(from: 0, to: memories.count, by: Self.upsertBatchSize) {
            let end = min(start + Self.upsertBatchSize, memories.count)
            let points = memories[start..<end].map { memory in
                UpsertPoint(
                    id: memory.id.uuidString,
                    vector: memory.visualEmbedding,
                    payload: PointPayload(memoryID: memory.id.uuidString)
                )
            }
            _ = try requiredBridge().upsert(json: Self.encode(UpsertRequest(points: points)))
        }
    }

    private func flushBridge() throws {
        _ = try requiredBridge().flush()
    }

    private func requiredBridge() throws -> any QdrantEdgeSession {
        guard !isBridgeDisabled else {
            throw QdrantVectorMemoryStoreError.bridgeDisabled
        }
        guard let bridge else {
            throw QdrantVectorMemoryStoreError.bridgeNotInitialized
        }
        return bridge
    }

    private func disableBridge() {
        bridge?.close()
        bridge = nil
        isBridgeDisabled = true
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }
}

protocol QdrantEdgeSession: Sendable {
    func upsert(json: Data) throws -> Data
    func query(json: Data) throws -> Data
    func flush() throws -> Data
    func close()
}

private final class LiveQdrantEdgeSession: QdrantEdgeSession, @unchecked Sendable {
    private let client: EdgeBridgeClient

    init(createJSON: Data) throws {
        client = try EdgeBridgeClient(createJSON: createJSON)
    }

    func upsert(json: Data) throws -> Data {
        try client.upsert(json: json)
    }

    func query(json: Data) throws -> Data {
        try client.query(json: json)
    }

    func flush() throws -> Data {
        try client.flush()
    }

    func close() {
        client.close()
    }
}

private struct CreateRequest: Encodable {
    let path: String
    let vectorSize: Int
    let distance: String
    let onDiskPayload: Bool
    let onDiskVectors: Bool
    let openExisting: Bool
    let maxSearchThreads: Int
}

private struct UpsertRequest: Encodable {
    let points: [UpsertPoint]
}

private struct UpsertPoint: Encodable {
    let id: String
    let vector: [Float]
    let payload: PointPayload
}

private struct PointPayload: Encodable {
    let memoryID: String
}

private struct QueryRequest: Encodable {
    let vector: [Float]
    let limit: Int
    let withPayload: Bool
    let withVector: Bool
}

private struct QueryResponse: Decodable {
    let hits: [QueryHit]
}

private struct QueryHit: Decodable {
    let id: QdrantPointID
    let score: Double
}

private enum QdrantPointID: Decodable {
    case uuidString(String)
    case number(UInt64)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .uuidString(string)
        } else {
            self = .number(try container.decode(UInt64.self))
        }
    }

    var uuid: UUID? {
        guard case .uuidString(let value) = self else { return nil }
        return UUID(uuidString: value)
    }
}

private enum QdrantVectorMemoryStoreError: LocalizedError {
    case bridgeDisabled
    case bridgeNotInitialized
    case invalidVectorDimension(Int)
    case vectorDimensionMismatch(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .bridgeDisabled:
            "Qdrant Edgeはこのセッションで無効です"
        case .bridgeNotInitialized:
            "Qdrant Edgeを初期化できませんでした"
        case .invalidVectorDimension(let dimension):
            "画像ベクトルの次元が不正です: \(dimension)"
        case .vectorDimensionMismatch(let expected, let actual):
            "画像ベクトルの次元が一致しません（期待: \(expected)、実際: \(actual)）"
        }
    }
}
#endif
