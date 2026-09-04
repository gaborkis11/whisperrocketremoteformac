import Foundation

/// Uploads one recording to the host's `/dictate` endpoint.
///
/// The body is the raw audio file, not a multipart form: that is what the
/// host's `phone_endpoint.py` expects, and streaming it straight from disk
/// keeps a five-minute recording out of memory.
///
/// The host answers HTTP/1.0 and closes the connection after every response,
/// so nothing here may assume a reused socket: each upload is one exchange,
/// and a connection that dies under us is reported as a retryable transport
/// failure rather than a dead host.
public struct DictationClient: Sendable {
    public static let modeHeader = "X-WhisperRocket-Mode"
    public static let enhancedHeader = "X-WhisperRocket-Enhanced"
    public static let contentType = "audio/mp4"
    public static let defaultRequestTimeout: TimeInterval = 120
    public static let defaultResourceTimeout: TimeInterval = 300

    private let session: URLSession
    private let requestTimeout: TimeInterval

    /// - Parameter session: injectable so tests can drive a `URLProtocol` stub.
    public init(
        session: URLSession = DictationClient.makeSession(),
        requestTimeout: TimeInterval = DictationClient.defaultRequestTimeout
    ) {
        self.session = session
        self.requestTimeout = requestTimeout
    }

    /// A five-minute transcription plus an AI pass can keep the socket open for
    /// a long time, so the per-request ceiling is generous; the resource
    /// ceiling bounds the whole exchange.
    public static func makeSession(
        requestTimeout: TimeInterval = defaultRequestTimeout,
        resourceTimeout: TimeInterval = defaultResourceTimeout
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        // Fail fast into stored mode instead of parking the upload until the
        // network comes back; the recording is safe on disk either way.
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    public func makeRequest(config: EndpointConfig) -> URLRequest {
        var request = URLRequest(url: config.url)
        request.httpMethod = "POST"
        request.setValue(config.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue(Self.contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = requestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    public func send(fileURL: URL, config: EndpointConfig) async -> DictationOutcome {
        // URLSession would happily hand a custom URLProtocol an empty body for
        // a missing file, and a silently empty upload is the one failure the
        // user could not diagnose. Fail here, with a kind that never retries.
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            return .failure(kind: .audioUnreadable(fileURL.lastPathComponent), serverMessage: nil)
        }
        do {
            let (data, response) = try await session.upload(for: makeRequest(config: config), fromFile: fileURL)
            return Self.outcome(data: data, response: response)
        } catch {
            return .failure(kind: DictationFailureKind(error: error), serverMessage: nil)
        }
    }

    static func outcome(data: Data, response: URLResponse) -> DictationOutcome {
        guard let http = response as? HTTPURLResponse else {
            return .failure(kind: .transport("no HTTP response"), serverMessage: nil)
        }
        let body = String(data: data, encoding: .utf8)
        guard (200..<300).contains(http.statusCode) else {
            return .failure(
                kind: DictationFailureKind(httpStatus: http.statusCode),
                serverMessage: body?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            )
        }
        return .success(
            text: body ?? "",
            mode: DictationMode(headerValue: http.value(forHTTPHeaderField: modeHeader)),
            enhanced: Self.parseBool(http.value(forHTTPHeaderField: enhancedHeader))
        )
    }

    static func parseBool(_ value: String?) -> Bool {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return ["true", "1", "yes", "on"].contains(value)
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
