import Foundation
import XCTest
@testable import KIOKURelay

final class OpenAIResponsesClientTests: XCTestCase {
    func testBatchRequestIncludesEveryImageInChronologicalOrder() throws {
        let frames = [
            Data("first-frame".utf8),
            Data("second-frame".utf8),
            Data("third-frame".utf8)
        ]

        let request = try OpenAIResponsesClient.makeAnalysisRequest(
            apiKey: "sk-test-only",
            jpegData: frames
        )
        let bodyData = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        )
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let message = try XCTUnwrap(input.first)
        let content = try XCTUnwrap(message["content"] as? [[String: Any]])

        XCTAssertEqual(
            content.compactMap { $0["type"] as? String },
            [
                "input_text",
                "input_text", "input_image",
                "input_text", "input_image",
                "input_text", "input_image"
            ]
        )

        let imageItems = content.filter { ($0["type"] as? String) == "input_image" }
        XCTAssertEqual(imageItems.count, frames.count)
        XCTAssertEqual(
            imageItems.compactMap { $0["image_url"] as? String },
            frames.map { "data:image/jpeg;base64,\($0.base64EncodedString())" }
        )
        XCTAssertTrue(imageItems.allSatisfy { ($0["detail"] as? String) == "low" })

        let frameLabels = content
            .filter { ($0["type"] as? String) == "input_text" }
            .dropFirst()
            .compactMap { $0["text"] as? String }
        XCTAssertEqual(
            frameLabels,
            ["フレーム 0（1/3）", "フレーム 1（2/3）", "フレーム 2（3/3）"]
        )
    }

    func testBatchResponseReturnsOneAnalysisForEachFrameInOrder() throws {
        let data = try makeResponseData(observations: [
            observation(index: 0, title: "玄関の鍵"),
            observation(index: 1, title: "机の財布"),
            observation(index: 2, title: "棚の眼鏡")
        ])

        let analyses = try OpenAIResponsesClient.parseAnalysisResponse(
            data,
            expectedFrameCount: 3
        )

        XCTAssertEqual(analyses.map(\.title), ["玄関の鍵", "机の財布", "棚の眼鏡"])
        XCTAssertEqual(analyses.map(\.summary), ["summary-0", "summary-1", "summary-2"])
        XCTAssertEqual(analyses.map(\.placeHint), ["place-0", "place-1", "place-2"])
    }

    func testBatchResponseRejectsMissingFrameAnalysis() throws {
        let data = try makeResponseData(observations: [
            observation(index: 0, title: "first")
        ])

        XCTAssertThrowsError(
            try OpenAIResponsesClient.parseAnalysisResponse(data, expectedFrameCount: 2)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("画像数と一致しません"))
        }
    }

    func testBatchResponseRejectsOutOfOrderFrameIndices() throws {
        let data = try makeResponseData(observations: [
            observation(index: 1, title: "second"),
            observation(index: 0, title: "first")
        ])

        XCTAssertThrowsError(
            try OpenAIResponsesClient.parseAnalysisResponse(data, expectedFrameCount: 2)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("時系列順ではありません"))
        }
    }

    func testBatchRequestRejectsEmptyFrameList() {
        XCTAssertThrowsError(
            try OpenAIResponsesClient.makeAnalysisRequest(apiKey: "sk-test-only", jpegData: [])
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("画像がありません"))
        }
    }

    private func observation(index: Int, title: String) -> [String: Any] {
        [
            "frameIndex": index,
            "title": title,
            "summary": "summary-\(index)",
            "placeHint": "place-\(index)",
            "tags": ["tag-\(index)"],
            "objects": ["object-\(index)"]
        ]
    }

    private func makeResponseData(observations: [[String: Any]]) throws -> Data {
        let payload = try JSONSerialization.data(
            withJSONObject: ["observations": observations],
            options: [.sortedKeys]
        )
        let jsonText = try XCTUnwrap(String(data: payload, encoding: .utf8))
        return try JSONSerialization.data(withJSONObject: [
            "output": [[
                "content": [[
                    "type": "output_text",
                    "text": jsonText
                ]]
            ]]
        ])
    }
}
