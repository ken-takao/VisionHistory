import SwiftUI
import UIKit

struct CapturedMemoryFrame {
    let image: CGImage
    let capturedAt: Date
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var memories: [MemoryItem] = []
    @Published private(set) var searchResults: [ScoredMemory] = []
    @Published private(set) var serviceStatuses: [ServiceStatus]
    @Published var isBusy = false
    @Published var lastMessage: String?
    @Published var cloudEnrichmentEnabled = true
    @Published private(set) var speechState: SpeechPlaybackState = .idle

    let secrets: AppSecrets
    private var store: any VectorMemoryStore
    private var usesQdrantStore: Bool
    private let visionEmbedder = VisionFeaturePrintEmbedder()
    private let textEmbedder = AppleTextEmbedder()
    private let openAI: OpenAIResponsesClient
    private let neo4j: Neo4jQueryClient
    private let shisa: ShisaVoiceClient
    private let shisaAudioPlayer = ShisaAudioPlayer()
    private var speechRequestID: UUID?

    init(secrets: AppSecrets = AppSecrets(), store: (any VectorMemoryStore)? = nil) {
        self.secrets = secrets
        if let store {
            self.store = store
            usesQdrantStore = false
        } else {
#if canImport(EdgeBridge)
            self.store = QdrantVectorMemoryStore()
            usesQdrantStore = true
#else
            self.store = FileVectorMemoryStore()
            usesQdrantStore = false
#endif
        }
        openAI = OpenAIResponsesClient(apiKey: secrets.openAIAPIKey)
        neo4j = Neo4jQueryClient(
            host: secrets.neo4jHost,
            database: secrets.neo4jDatabase,
            username: secrets.neo4jUsername,
            password: secrets.neo4jPassword
        )
        shisa = ShisaVoiceClient(apiKey: secrets.shisaAPIKey)
        serviceStatuses = [
            ServiceStatus(kind: .localAI, state: .local),
            ServiceStatus(kind: .qdrant, state: usesQdrantStore ? .checking : .local),
            ServiceStatus(kind: .openAI, state: secrets.hasOpenAI ? .checking : .notConfigured),
            ServiceStatus(kind: .neo4j, state: secrets.hasNeo4j ? .checking : .notConfigured),
            ServiceStatus(kind: .shisa, state: secrets.hasShisa ? .checking : .notConfigured)
        ]
    }

    func bootstrap() async {
        do {
            memories = try await store.loadAll()
            searchResults = memories.map { ScoredMemory(memory: $0, score: 1) }
            if usesQdrantStore {
                setStatus(.qdrant, .local)
            }
        } catch {
            if usesQdrantStore {
                await fallBackToFileStore(qdrantError: error)
            } else {
                lastMessage = error.localizedDescription
            }
        }
        await checkConnections()
    }

    func checkConnections() async {
        await check(kind: .openAI, configured: secrets.hasOpenAI) {
            try await self.openAI.checkConnection()
        }
        await check(kind: .neo4j, configured: secrets.hasNeo4j) {
            try await self.neo4j.checkConnection()
        }
        await check(kind: .shisa, configured: secrets.hasShisa) {
            try await self.shisa.checkConnection()
        }
    }

    func search(_ query: String) async {
        let vector = await textEmbedder.embedding(for: query)
        do {
            searchResults = try await store.search(text: query, textEmbedding: vector, limit: 30)
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    func speak(_ memory: MemoryItem) async {
        guard secrets.hasShisa else {
            lastMessage = "Shisa APIキーが未設定です"
            return
        }

        if speechState.memoryID == memory.id {
            speechRequestID = nil
            shisaAudioPlayer.stop()
            speechState = .idle
            return
        }

        speechRequestID = nil
        shisaAudioPlayer.stop()
        let requestID = UUID()
        speechRequestID = requestID
        speechState = .loading(memory.id)

        do {
            let audio = try await shisa.synthesizeJapanese(text: spokenSummary(for: memory))
            guard speechRequestID == requestID else { return }
            try shisaAudioPlayer.play(audio) { [weak self] in
                guard let self, self.speechRequestID == requestID else { return }
                self.speechRequestID = nil
                self.speechState = .idle
            }
            speechState = .playing(memory.id)
        } catch {
            guard speechRequestID == requestID else { return }
            speechRequestID = nil
            speechState = .idle
            lastMessage = "読み上げを開始できませんでした: \(error.localizedDescription)"
        }
    }

    func captureMemory(from image: CGImage, useCloud: Bool) async -> MemoryItem? {
        await captureMemories(
            from: [CapturedMemoryFrame(image: image, capturedAt: .now)],
            useCloud: useCloud
        ).first
    }

    func captureMemories(from frames: [CapturedMemoryFrame], useCloud: Bool) async -> [MemoryItem] {
        guard !frames.isEmpty else {
            lastMessage = "記憶できるフレームがありませんでした"
            return []
        }

        isBusy = true
        defer { isBusy = false }

        do {
            var preparedFrames: [PreparedMemoryFrame] = []
            preparedFrames.reserveCapacity(frames.count)
            for frame in frames {
                if Task.isCancelled { return [] }
                let visualEmbedding = try await visionEmbedder.embedding(for: frame.image)
                let uiImage = UIImage(cgImage: frame.image)
                guard let jpegData = uiImage.jpegData(compressionQuality: 0.62) else {
                    throw ServiceError.malformedPayload("撮影画像を保存できませんでした")
                }
                preparedFrames.append(
                    PreparedMemoryFrame(
                        capturedAt: frame.capturedAt,
                        jpegData: jpegData,
                        visualEmbedding: visualEmbedding
                    )
                )
            }

            let shouldEnrichWithOpenAI = useCloud && cloudEnrichmentEnabled && secrets.hasOpenAI
            var analyses = Array(repeating: ImageAnalysis.localFallback, count: preparedFrames.count)
            var openAIFailure: Error?
            if shouldEnrichWithOpenAI {
                do {
                    analyses = try await openAI.analyze(jpegData: preparedFrames.map(\.jpegData))
                } catch {
                    openAIFailure = error
                }
            }

            var savedMemories: [MemoryItem] = []
            savedMemories.reserveCapacity(preparedFrames.count)
            var duplicateCount = 0
            var neo4jFailureCount = 0
            let memoriesBeforeScan = try await store.loadAll()
            let memoryIDsBeforeScan = Set(memoriesBeforeScan.map(\.id))

            for (prepared, analysis) in zip(preparedFrames, analyses) {
                let searchableText = (
                    [analysis.title, analysis.summary, analysis.placeHint]
                        + analysis.tags
                        + analysis.objects
                ).joined(separator: " ")
                let textEmbedding = await textEmbedder.embedding(for: searchableText)
                var memory = MemoryItem(
                    title: analysis.title,
                    summary: analysis.summary,
                    capturedAt: prepared.capturedAt,
                    place: analysis.placeHint,
                    tags: Array(Set(analysis.tags + analysis.objects)).sorted(),
                    symbolName: "viewfinder",
                    thumbnailJPEG: prepared.jpegData,
                    visualEmbedding: prepared.visualEmbedding,
                    textEmbedding: textEmbedding
                )

                let similar = try await store.searchSimilar(
                    visualEmbedding: prepared.visualEmbedding,
                    limit: preparedFrames.count + 1
                )
                // Frames already saved by this scan are intentionally not treated as
                // duplicates: every sampled frame keeps its own OpenAI metadata. We
                // only suppress a near-identical memory that predates this scan.
                if let nearest = similar.first(where: { memoryIDsBeforeScan.contains($0.memory.id) }),
                   nearest.score > 0.985,
                   prepared.capturedAt.timeIntervalSince(nearest.memory.capturedAt) < 60 {
                    duplicateCount += 1
                    continue
                }

                try await store.upsert(memory)
                if useCloud, secrets.hasNeo4j {
                    do {
                        try await neo4j.recordObservation(memory)
                        memory.neo4jSynced = true
                        try await store.upsert(memory)
                    } catch {
                        neo4jFailureCount += 1
                    }
                }
                savedMemories.append(memory)
            }

            memories = try await store.loadAll()
            searchResults = memories.map { ScoredMemory(memory: $0, score: 1) }

            if let openAIFailure {
                lastMessage = "\(preparedFrames.count)枚を処理し、\(savedMemories.count)件を端末に保存しました。OpenAIメタ情報の取得に失敗しました: \(openAIFailure.localizedDescription)"
            } else if savedMemories.isEmpty {
                lastMessage = "\(preparedFrames.count)枚を解析しましたが、すべて既存の記憶と重複していました"
            } else {
                let enrichment = shouldEnrichWithOpenAI ? "OpenAIで全画像を解析し、" : ""
                let duplicateNote = duplicateCount > 0 ? "（重複\(duplicateCount)枚を除外）" : ""
                lastMessage = "\(enrichment)\(savedMemories.count)件を記憶しました\(duplicateNote)"
            }
            if neo4jFailureCount > 0 {
                lastMessage = (lastMessage ?? "端末に保存しました")
                    + " / Neo4j未同期: \(neo4jFailureCount)件"
            }
            return savedMemories
        } catch {
            if let latestMemories = try? await store.loadAll() {
                memories = latestMemories
                searchResults = latestMemories.map { ScoredMemory(memory: $0, score: 1) }
            }
            lastMessage = error.localizedDescription
            return []
        }
    }

    private func check(
        kind: ServiceKind,
        configured: Bool,
        operation: () async throws -> Void
    ) async {
        guard configured else {
            setStatus(kind, .notConfigured)
            return
        }
        setStatus(kind, .checking)
        do {
            try await operation()
            setStatus(kind, .connected)
        } catch {
            setStatus(kind, .failed(error.localizedDescription))
        }
    }

    private func setStatus(_ kind: ServiceKind, _ state: ConnectionState) {
        guard let index = serviceStatuses.firstIndex(where: { $0.kind == kind }) else { return }
        serviceStatuses[index].state = state
    }

    private func fallBackToFileStore(qdrantError: Error) async {
        let fallback = FileVectorMemoryStore()
        store = fallback
        usesQdrantStore = false

        do {
            memories = try await fallback.loadAll()
            searchResults = memories.map { ScoredMemory(memory: $0, score: 1) }
            let message = "Qdrant Edgeを開始できなかったため、JSONファイル保存へ切り替えました"
            setStatus(.qdrant, .failed(message))
            lastMessage = message
        } catch {
            let message = "Qdrant Edgeとファイル保存の初期化に失敗しました: \(error.localizedDescription)"
            setStatus(.qdrant, .failed(message))
            lastMessage = message + " / Qdrant: " + qdrantError.localizedDescription
        }
    }

    private func spokenSummary(for memory: MemoryItem) -> String {
        let title = memory.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = memory.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = memory.place.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !title.isEmpty { parts.append("\(title)。") }
        if !summary.isEmpty { parts.append(summary) }
        if !place.isEmpty { parts.append("場所は\(place)です。") }
        return parts.joined(separator: " ")
    }

    private struct PreparedMemoryFrame {
        let capturedAt: Date
        let jpegData: Data
        let visualEmbedding: [Float]
    }
}
