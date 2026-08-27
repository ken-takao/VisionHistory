#if canImport(EdgeBridge)
import Foundation
import XCTest
@testable import KIOKURelay

final class QdrantVectorMemoryStoreFailureTests: XCTestCase {
    func testInitializationFailureDisablesBridgeAndFallsBackToCosineSearch() async throws {
        let memory = makeMemory(vector: [1, 0])
        let metadata = InMemoryVectorMemoryStore(memories: [memory])
        let factory = BridgeFactoryProbe(failure: .initialization)
        let store = makeStore(metadata: metadata, factory: factory)

        let loaded = try await store.loadAll()
        let firstSearch = try await store.searchSimilar(visualEmbedding: [1, 0], limit: 1)
        let secondSearch = try await store.searchSimilar(visualEmbedding: [1, 0], limit: 1)

        XCTAssertEqual(loaded.map(\.id), [memory.id])
        XCTAssertEqual(firstSearch.first?.memory.id, memory.id)
        XCTAssertEqual(firstSearch.first?.score ?? 0, 1, accuracy: 0.000_001)
        XCTAssertEqual(secondSearch.first?.memory.id, memory.id)
        XCTAssertEqual(factory.createCount, 1, "A disabled bridge must not be retried this session")
    }

    func testBackfillFlushFailureClosesBridgeAndDoesNotRetry() async throws {
        let memory = makeMemory(vector: [1, 0])
        let metadata = InMemoryVectorMemoryStore(memories: [memory])
        let session = BridgeSessionProbe(failure: .flush)
        let factory = BridgeFactoryProbe(session: session)
        let store = makeStore(metadata: metadata, factory: factory)

        _ = try await store.loadAll()
        let result = try await store.searchSimilar(visualEmbedding: [1, 0], limit: 1)
        _ = try await store.loadAll()

        XCTAssertEqual(result.first?.memory.id, memory.id)
        XCTAssertEqual(session.upsertCount, 1)
        XCTAssertEqual(session.flushCount, 1)
        XCTAssertEqual(session.queryCount, 0)
        XCTAssertEqual(session.closeCount, 1)
        XCTAssertEqual(factory.createCount, 1)
    }

    func testUpsertFailureIsNonFatalAndMetadataRemainsAuthoritative() async throws {
        let metadata = InMemoryVectorMemoryStore()
        let session = BridgeSessionProbe(failure: .upsert)
        let factory = BridgeFactoryProbe(session: session)
        let store = makeStore(metadata: metadata, factory: factory)
        let first = makeMemory(vector: [1, 0])
        let second = makeMemory(vector: [0, 1])

        try await store.upsert(first)
        try await store.upsert(second)
        let saved = try await metadata.loadAll()
        let result = try await store.searchSimilar(visualEmbedding: [1, 0], limit: 1)

        XCTAssertEqual(Set(saved.map(\.id)), Set([first.id, second.id]))
        XCTAssertEqual(result.first?.memory.id, first.id)
        XCTAssertEqual(session.upsertCount, 1)
        XCTAssertEqual(session.flushCount, 0)
        XCTAssertEqual(session.closeCount, 1)
        XCTAssertEqual(factory.createCount, 1)
    }

    func testQueryFailureClosesBridgeAndFallsBackWithoutRetrying() async throws {
        let memory = makeMemory(vector: [1, 0])
        let metadata = InMemoryVectorMemoryStore(memories: [memory])
        let session = BridgeSessionProbe(failure: .query)
        let factory = BridgeFactoryProbe(session: session)
        let store = makeStore(metadata: metadata, factory: factory)

        _ = try await store.loadAll()
        let firstSearch = try await store.searchSimilar(visualEmbedding: [1, 0], limit: 1)
        let secondSearch = try await store.searchSimilar(visualEmbedding: [1, 0], limit: 1)

        XCTAssertEqual(firstSearch.first?.memory.id, memory.id)
        XCTAssertEqual(secondSearch.first?.memory.id, memory.id)
        XCTAssertEqual(session.upsertCount, 1)
        XCTAssertEqual(session.flushCount, 1)
        XCTAssertEqual(session.queryCount, 1)
        XCTAssertEqual(session.closeCount, 1)
        XCTAssertEqual(factory.createCount, 1)
    }

    private func makeStore(
        metadata: InMemoryVectorMemoryStore,
        factory: BridgeFactoryProbe
    ) -> QdrantVectorMemoryStore {
        QdrantVectorMemoryStore(
            metadataStore: metadata,
            shardURL: FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString, directoryHint: .isDirectory),
            bridgeFactory: { try factory.make(createJSON: $0) }
        )
    }

    private func makeMemory(vector: [Float]) -> MemoryItem {
        MemoryItem(
            title: "Test",
            summary: "Failure-injection fixture",
            place: "Test",
            tags: [],
            visualEmbedding: vector
        )
    }
}

private actor InMemoryVectorMemoryStore: VectorMemoryStore {
    private var memories: [MemoryItem]

    init(memories: [MemoryItem] = []) {
        self.memories = memories
    }

    func loadAll() -> [MemoryItem] {
        memories
    }

    func upsert(_ memory: MemoryItem) {
        if let index = memories.firstIndex(where: { $0.id == memory.id }) {
            memories[index] = memory
        } else {
            memories.append(memory)
        }
    }

    func markNeo4jSynced(id: UUID) {
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return }
        memories[index].neo4jSynced = true
    }

    func search(text: String, textEmbedding: [Float], limit: Int) -> [ScoredMemory] {
        []
    }

    func searchSimilar(visualEmbedding: [Float], limit: Int) -> [ScoredMemory] {
        memories
            .filter { !$0.visualEmbedding.isEmpty }
            .map {
                ScoredMemory(
                    memory: $0,
                    score: VectorMath.cosine(visualEmbedding, $0.visualEmbedding)
                )
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}

private final class BridgeFactoryProbe: @unchecked Sendable {
    enum Failure {
        case initialization
    }

    private let session: BridgeSessionProbe?
    private let failure: Failure?
    private(set) var createCount = 0

    init(session: BridgeSessionProbe) {
        self.session = session
        failure = nil
    }

    init(failure: Failure) {
        session = nil
        self.failure = failure
    }

    func make(createJSON: Data) throws -> any QdrantEdgeSession {
        _ = createJSON
        createCount += 1
        if failure != nil {
            throw FailureInjectionError.forced
        }
        return session!
    }
}

private final class BridgeSessionProbe: QdrantEdgeSession, @unchecked Sendable {
    enum Failure {
        case upsert
        case query
        case flush
    }

    private let failure: Failure
    private(set) var upsertCount = 0
    private(set) var queryCount = 0
    private(set) var flushCount = 0
    private(set) var closeCount = 0

    init(failure: Failure) {
        self.failure = failure
    }

    func upsert(json: Data) throws -> Data {
        _ = json
        upsertCount += 1
        if failure == .upsert {
            throw FailureInjectionError.forced
        }
        return Data("{}".utf8)
    }

    func query(json: Data) throws -> Data {
        _ = json
        queryCount += 1
        if failure == .query {
            throw FailureInjectionError.forced
        }
        return Data(#"{"hits":[]}"#.utf8)
    }

    func flush() throws -> Data {
        flushCount += 1
        if failure == .flush {
            throw FailureInjectionError.forced
        }
        return Data("{}".utf8)
    }

    func close() {
        closeCount += 1
    }
}

private enum FailureInjectionError: Error {
    case forced
}
#endif
