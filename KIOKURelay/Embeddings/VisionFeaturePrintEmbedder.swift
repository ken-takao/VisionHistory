import CoreGraphics
import Foundation
import Vision

struct VisionFeaturePrintEmbedder: Sendable {
    func embedding(for image: CGImage) async throws -> [Float] {
        let request = GenerateImageFeaturePrintRequest(.revision2)
        let observation = try await request.perform(on: image)
        let values: [Float]

        switch observation.elementType {
        case .float:
            values = observation.data.withUnsafeBytes { rawBuffer in
                Array(rawBuffer.bindMemory(to: Float.self).prefix(observation.elementCount))
            }
        case .double:
            values = observation.data.withUnsafeBytes { rawBuffer in
                rawBuffer.bindMemory(to: Double.self)
                    .prefix(observation.elementCount)
                    .map(Float.init)
            }
        @unknown default:
            throw ServiceError.malformedPayload("Visionの特徴量形式に対応していません")
        }

        return VectorMath.normalized(values)
    }
}
