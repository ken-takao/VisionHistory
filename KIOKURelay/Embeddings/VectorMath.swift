import Foundation

enum VectorMath {
    static func normalized(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }

    static func cosine(_ left: [Float], _ right: [Float]) -> Double {
        guard left.count == right.count, !left.isEmpty else { return 0 }
        var dot: Float = 0
        var leftMagnitude: Float = 0
        var rightMagnitude: Float = 0
        for index in left.indices {
            dot += left[index] * right[index]
            leftMagnitude += left[index] * left[index]
            rightMagnitude += right[index] * right[index]
        }
        guard leftMagnitude > 0, rightMagnitude > 0 else { return 0 }
        return Double(dot / sqrt(leftMagnitude * rightMagnitude))
    }
}
