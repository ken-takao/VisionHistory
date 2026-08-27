#if canImport(EdgeBridge)
import EdgeBridge
import Foundation

/// Thin synchronous owner for the Rust shard handle.
///
/// Qdrant operations can perform filesystem I/O. Invoke this wrapper from an
/// actor or a non-main executor in application code. Do not race `close()`
/// with an operation.
public final class EdgeBridgeClient {
    private var handle: OpaquePointer?

    public init(createJSON: Data) throws {
        var response: UnsafeMutablePointer<CChar>?
        let created: OpaquePointer? = try Self.withCString(createJSON) { request in
            qeb_create(request, &response)
        }
        let responseData = try Self.takeResponse(response)
        guard let created else {
            throw EdgeBridgeClientError.bridge(status: -1, response: responseData)
        }
        handle = created
    }

    deinit {
        if let handle {
            qeb_destroy(handle)
        }
    }

    public func upsert(json: Data) throws -> Data {
        try perform(json: json, operation: qeb_upsert)
    }

    public func query(json: Data) throws -> Data {
        try perform(json: json, operation: qeb_query)
    }

    public func flush() throws -> Data {
        try perform(json: Data("{}".utf8), operation: qeb_flush)
    }

    public func close() {
        if let handle {
            qeb_destroy(handle)
            self.handle = nil
        }
    }

    private func perform(
        json: Data,
        operation: (
            OpaquePointer?,
            UnsafePointer<CChar>?,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        ) -> Int32
    ) throws -> Data {
        guard let handle else {
            throw EdgeBridgeClientError.closed
        }
        var response: UnsafeMutablePointer<CChar>?
        let status = try Self.withCString(json) { request in
            operation(handle, request, &response)
        }
        let responseData = try Self.takeResponse(response)
        guard status == Int32(QEB_OK.rawValue) else {
            throw EdgeBridgeClientError.bridge(status: status, response: responseData)
        }
        return responseData
    }

    private static func withCString<T>(
        _ data: Data,
        _ body: (UnsafePointer<CChar>) throws -> T
    ) throws -> T {
        guard let string = String(data: data, encoding: .utf8) else {
            throw EdgeBridgeClientError.requestIsNotUTF8
        }
        return try string.withCString(body)
    }

    private static func takeResponse(
        _ pointer: UnsafeMutablePointer<CChar>?
    ) throws -> Data {
        guard let pointer else {
            throw EdgeBridgeClientError.missingResponse
        }
        defer { qeb_string_free(pointer) }
        return Data(bytes: pointer, count: strlen(pointer))
    }
}

public enum EdgeBridgeClientError: Error {
    case closed
    case requestIsNotUTF8
    case missingResponse
    case bridge(status: Int32, response: Data)
}

extension EdgeBridgeClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .closed:
            "Qdrant Edge bridge is closed"
        case .requestIsNotUTF8:
            "Qdrant Edge request is not UTF-8"
        case .missingResponse:
            "Qdrant Edge returned no response"
        case .bridge(let status, let response):
            "Qdrant Edge failed (status \(status)): \(String(decoding: response, as: UTF8.self))"
        }
    }
}
#endif
