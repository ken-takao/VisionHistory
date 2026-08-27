import Foundation

actor OpenAIResponsesClient {
    private let apiKey: String
    private let session: URLSession
    private let model = "gpt-5.6-luna"

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
        guard apiKey.hasPrefix("sk-") else {
            throw ServiceError.notConfigured("OpenAI")
        }

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "title": ["type": "string"],
                "summary": ["type": "string"],
                "placeHint": ["type": "string"],
                "tags": ["type": "array", "items": ["type": "string"]],
                "objects": ["type": "array", "items": ["type": "string"]]
            ],
            "required": ["title", "summary", "placeHint", "tags", "objects"]
        ]

        let body: [String: Any] = [
            "model": model,
            "store": false,
            "reasoning": ["effort": "none"],
            "max_output_tokens": 800,
            "input": [[
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": "この画像を『あとで物の場所を思い出す』用途で日本語解析してください。個人の身元推測はせず、見えている物・色・置き場所だけを簡潔に記録してください。"
                    ],
                    [
                        "type": "input_image",
                        "image_url": "data:image/jpeg;base64,\(jpegData.base64EncodedString())",
                        "detail": "low"
                    ]
                ]
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
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try Self.validate(data: data, response: response, service: "OpenAI")

        let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        guard let jsonText = envelope.output
            .flatMap({ $0.content ?? [] })
            .first(where: { $0.type == "output_text" })?
            .text,
              let jsonData = jsonText.data(using: .utf8)
        else {
            throw ServiceError.malformedPayload("OpenAIの画像解析結果が空でした")
        }
        return try JSONDecoder().decode(ImageAnalysis.self, from: jsonData)
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
