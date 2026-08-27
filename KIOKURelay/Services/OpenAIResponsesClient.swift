import Foundation

actor OpenAIResponsesClient {
    private let apiKey: String
    private let session: URLSession
    private static let model = "gpt-5.6-luna"

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func checkConnection() async throws {
        guard apiKey.hasPrefix("sk-") else {
            throw ServiceError.notConfigured("OpenAI")
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try Self.validate(data: data, response: response, service: "OpenAI")
    }

    func analyze(jpegData: Data) async throws -> ImageAnalysis {
        guard let analysis = try await analyze(jpegData: [jpegData]).first else {
            throw ServiceError.malformedPayload("OpenAIの画像解析結果が空でした")
        }
        return analysis
    }

    func analyze(jpegData: [Data]) async throws -> [ImageAnalysis] {
        guard apiKey.hasPrefix("sk-") else {
            throw ServiceError.notConfigured("OpenAI")
        }

        let request = try Self.makeAnalysisRequest(apiKey: apiKey, jpegData: jpegData)
        let (data, response) = try await session.data(for: request)
        try Self.validate(data: data, response: response, service: "OpenAI")
        return try Self.parseAnalysisResponse(data, expectedFrameCount: jpegData.count)
    }

    static func makeAnalysisRequest(apiKey: String, jpegData: [Data]) throws -> URLRequest {
        guard !jpegData.isEmpty else {
            throw ServiceError.malformedPayload("OpenAIへ送る画像がありません")
        }

        let observationSchema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "frameIndex": ["type": "integer"],
                "title": ["type": "string"],
                "summary": ["type": "string"],
                "placeHint": ["type": "string"],
                "tags": ["type": "array", "items": ["type": "string"]],
                "objects": ["type": "array", "items": ["type": "string"]]
            ],
            "required": ["frameIndex", "title", "summary", "placeHint", "tags", "objects"]
        ]
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "observations": [
                    "type": "array",
                    "description": "入力フレームと同じ件数を、frameIndexの昇順で返す",
                    "items": observationSchema
                ]
            ],
            "required": ["observations"]
        ]

        var content: [[String: Any]] = [[
            "type": "input_text",
            "text": "この後の\(jpegData.count)枚は時系列順のフレームです。各フレームを『あとで物の場所を思い出す』用途で日本語解析してください。個人の身元推測はせず、見えている物・色・置き場所だけを簡潔に記録してください。observationsには各入力フレームにつき必ず1件を、0始まりのframeIndex順で返してください。前後のフレームも文脈として使えますが、各観測は対応するフレームで確認できる内容にしてください。"
        ]]
        for (index, frame) in jpegData.enumerated() {
            content.append([
                "type": "input_text",
                "text": "フレーム \(index)（\(index + 1)/\(jpegData.count)）"
            ])
            content.append([
                "type": "input_image",
                "image_url": "data:image/jpeg;base64,\(frame.base64EncodedString())",
                "detail": "low"
            ])
        }

        let body: [String: Any] = [
            "model": model,
            "store": false,
            "reasoning": ["effort": "none"],
            "max_output_tokens": max(800, jpegData.count * 300),
            "input": [[
                "role": "user",
                "content": content
            ]],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "memory_observation",
                    "strict": true,
                    "schema": schema
                ]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func parseAnalysisResponse(_ data: Data, expectedFrameCount: Int) throws -> [ImageAnalysis] {
        let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        guard let jsonText = envelope.output
            .flatMap({ $0.content ?? [] })
            .first(where: { $0.type == "output_text" })?
            .text,
              let jsonData = jsonText.data(using: .utf8)
        else {
            throw ServiceError.malformedPayload("OpenAIの画像解析結果が空でした")
        }
        let batch = try JSONDecoder().decode(IndexedAnalysisBatch.self, from: jsonData)
        guard batch.observations.count == expectedFrameCount else {
            throw ServiceError.malformedPayload(
                "OpenAIの解析件数が画像数と一致しません（画像\(expectedFrameCount)枚 / 解析\(batch.observations.count)件）"
            )
        }
        guard batch.observations.enumerated().allSatisfy({ offset, observation in
            observation.frameIndex == offset
        }) else {
            throw ServiceError.malformedPayload("OpenAIの解析結果がフレームの時系列順ではありません")
        }
        return batch.observations.map(\.analysis)
    }

    private static func validate(data: Data, response: URLResponse, service: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let safeMessage = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data).error.message)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw ServiceError.http(service: service, status: http.statusCode, message: safeMessage)
        }
    }
}

private struct IndexedAnalysisBatch: Decodable {
    let observations: [IndexedImageAnalysis]
}

private struct IndexedImageAnalysis: Decodable {
    let frameIndex: Int
    let title: String
    let summary: String
    let placeHint: String
    let tags: [String]
    let objects: [String]

    var analysis: ImageAnalysis {
        ImageAnalysis(
            title: title,
            summary: summary,
            placeHint: placeHint,
            tags: tags,
            objects: objects
        )
    }
}

private struct ResponseEnvelope: Decodable {
    struct OutputItem: Decodable {
        struct ContentItem: Decodable {
            let type: String
            let text: String?
        }

        let content: [ContentItem]?
    }

    let output: [OutputItem]
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}
