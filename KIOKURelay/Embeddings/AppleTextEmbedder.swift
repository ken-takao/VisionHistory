import Foundation
import NaturalLanguage

actor AppleTextEmbedder {
    private var model: NLContextualEmbedding?

    func embedding(for text: String) async -> [Float] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        do {
            let embeddingModel: NLContextualEmbedding
            if let model {
                embeddingModel = model
            } else if let japaneseModel = NLContextualEmbedding(language: .japanese) {
                model = japaneseModel
                embeddingModel = japaneseModel
            } else {
                return fallbackEmbedding(for: text)
            }

            if !embeddingModel.hasAvailableAssets {
                let result = try await embeddingModel.requestAssets()
                guard result == .available else { return fallbackEmbedding(for: text) }
            }

            try embeddingModel.load()
            let result = try embeddingModel.embeddingResult(for: text, language: .japanese)
            var pooled = [Float](repeating: 0, count: embeddingModel.dimension)
            var tokenCount: Float = 0

            result.enumerateTokenVectors(in: result.string.startIndex..<result.string.endIndex) { vector, range in
                guard !range.isEmpty else { return true }
                for (index, value) in vector.enumerated() where index < pooled.count {
                    pooled[index] += Float(value)
                }
                tokenCount += 1
                return true
            }

            guard tokenCount > 0 else { return fallbackEmbedding(for: text) }
            return VectorMath.normalized(pooled.map { $0 / tokenCount })
        } catch {
            return fallbackEmbedding(for: text)
        }
    }

    private func fallbackEmbedding(for text: String) -> [Float] {
        let dimension = 256
        var vector = [Float](repeating: 0, count: dimension)
        let scalars = Array(text.lowercased().unicodeScalars)
        guard !scalars.isEmpty else { return vector }

        for index in scalars.indices {
            let current = UInt64(scalars[index].value)
            let next = index + 1 < scalars.count ? UInt64(scalars[index + 1].value) : 0
            let hash = (current &* 1_099_511_628_211) ^ next
            let bucket = Int(hash % UInt64(dimension))
            vector[bucket] += 1
        }
        return VectorMath.normalized(vector)
    }
}
