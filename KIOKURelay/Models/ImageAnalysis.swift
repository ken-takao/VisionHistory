import Foundation

struct ImageAnalysis: Codable, Sendable {
    let title: String
    let summary: String
    let placeHint: String
    let tags: [String]
    let objects: [String]

    static let localFallback = ImageAnalysis(
        title: "新しい記憶",
        summary: "端末内で画像特徴を保存しました。",
        placeHint: "場所未設定",
        tags: ["スキャン"],
        objects: []
    )
}
