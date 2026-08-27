import Foundation

struct MemoryScanConfiguration: Equatable, Sendable {
    let durationSeconds: Int
    let keyframeIntervalSeconds: Int

    init(durationSeconds: Int, keyframeIntervalSeconds: Int) {
        precondition(durationSeconds > 0)
        precondition(keyframeIntervalSeconds > 0)
        precondition(durationSeconds.isMultiple(of: keyframeIntervalSeconds))
        self.durationSeconds = durationSeconds
        self.keyframeIntervalSeconds = keyframeIntervalSeconds
    }

    var targetKeyframeCount: Int {
        durationSeconds / keyframeIntervalSeconds
    }

    var keyframeOffsetsSeconds: [Int] {
        (1...targetKeyframeCount).map { $0 * keyframeIntervalSeconds }
    }

    static let standard = MemoryScanConfiguration(
        durationSeconds: 30,
        keyframeIntervalSeconds: 2
    )
}
