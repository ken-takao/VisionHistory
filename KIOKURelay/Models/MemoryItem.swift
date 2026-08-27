import Foundation

struct MemoryItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var summary: String
    var capturedAt: Date
    var place: String
    var tags: [String]
    var symbolName: String
    var thumbnailJPEG: Data?
    var visualEmbedding: [Float]
    var textEmbedding: [Float]
    var neo4jSynced: Bool

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        capturedAt: Date = .now,
        place: String,
        tags: [String],
        symbolName: String = "viewfinder",
        thumbnailJPEG: Data? = nil,
        visualEmbedding: [Float] = [],
        textEmbedding: [Float] = [],
        neo4jSynced: Bool = false
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.capturedAt = capturedAt
        self.place = place
        self.tags = tags
        self.symbolName = symbolName
        self.thumbnailJPEG = thumbnailJPEG
        self.visualEmbedding = visualEmbedding
        self.textEmbedding = textEmbedding
        self.neo4jSynced = neo4jSynced
    }
}

extension MemoryItem {
    static let demoItems: [MemoryItem] = [
        MemoryItem(
            title: "玄関の鍵",
            summary: "黒いキーホルダー付き。靴箱の上、白いトレーの右側。",
            capturedAt: .now.addingTimeInterval(-18 * 60),
            place: "玄関",
            tags: ["鍵", "黒", "トレー"],
            symbolName: "key.fill"
        ),
        MemoryItem(
            title: "USB-Cケーブル",
            summary: "短い白色ケーブル。仕事机の左側の引き出し。",
            capturedAt: .now.addingTimeInterval(-3_420),
            place: "仕事部屋",
            tags: ["ケーブル", "USB-C", "白"],
            symbolName: "cable.connector"
        ),
        MemoryItem(
            title: "役所からの封筒",
            summary: "青い文字の長形封筒。ダイニングテーブルの書類束。",
            capturedAt: .now.addingTimeInterval(-86_400),
            place: "ダイニング",
            tags: ["書類", "封筒", "役所"],
            symbolName: "envelope.fill"
        )
    ]
}
