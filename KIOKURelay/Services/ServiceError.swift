import Foundation

enum ServiceError: LocalizedError, Sendable {
    case notConfigured(String)
    case invalidResponse
    case http(service: String, status: Int, message: String)
    case malformedPayload(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let service):
            return "\(service) が未設定です"
        case .invalidResponse:
            return "サーバー応答を確認できませんでした"
        case .http(let service, let status, let message):
            return "\(service) \(status): \(message)"
        case .malformedPayload(let message):
            return message
        }
    }
}
