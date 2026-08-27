import XCTest
@testable import KIOKURelay

final class MemoryScanConfigurationTests: XCTestCase {
    func testStandardScanCapturesFifteenKeyframesAcrossThirtySeconds() {
        let configuration = MemoryScanConfiguration.standard

        XCTAssertEqual(configuration.durationSeconds, 30)
        XCTAssertEqual(configuration.keyframeIntervalSeconds, 2)
        XCTAssertEqual(configuration.targetKeyframeCount, 15)
        XCTAssertEqual(configuration.keyframeOffsetsSeconds, Array(stride(from: 2, through: 30, by: 2)))
        XCTAssertEqual(configuration.keyframeOffsetsSeconds.last, configuration.durationSeconds)
    }
}
