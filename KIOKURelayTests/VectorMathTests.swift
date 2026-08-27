import XCTest
@testable import KIOKURelay

final class VectorMathTests: XCTestCase {
    func testCosineOfIdenticalVectorsIsOne() {
        XCTAssertEqual(VectorMath.cosine([1, 2, 3], [1, 2, 3]), 1, accuracy: 0.000_001)
    }

    func testCosineOfOrthogonalVectorsIsZero() {
        XCTAssertEqual(VectorMath.cosine([1, 0], [0, 1]), 0, accuracy: 0.000_001)
    }

    func testCosineRejectsDifferentDimensions() {
        XCTAssertEqual(VectorMath.cosine([1, 2], [1]), 0)
    }

    func testNormalizationProducesUnitVector() {
        let normalized = VectorMath.normalized([3, 4])
        XCTAssertEqual(normalized[0], 0.6, accuracy: 0.000_001)
        XCTAssertEqual(normalized[1], 0.8, accuracy: 0.000_001)
    }
}
