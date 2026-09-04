import Foundation

/// What a `/health` probe found.
public enum HealthStatus: Equatable, Sendable {
    /// 2xx — the host will take a dictation right now.
    case ready
    /// 503 — the host is up but the model is still loading.
    case notReady(serverMessage: String?)
    /// 401 — the host is up and rejected the token. Worth its own case: the
    /// panel must say "wrong token", not "host unreachable".
    case unauthorized(serverMessage: String?)
    /// Any other status the host answered with.
    case unexpected(status: Int, serverMessage: String?)
    /// Nothing answered inside the probe's budget.
    case unreachable(kind: DictationFailureKind)

    /// Something answered — the host process is alive.
    public var isReachable: Bool {
        if case .unreachable = self { return false }
        return true
    }

    /// The flag that feeds `RecorderState.healthResult(reachable:)`: only a
    /// ready host means the dictation will land, so a loading model or a bad
    /// token still raises the panel's stored-mode banner.
    public var isReady: Bool { self == .ready }
}

/// Probes `/health` alongside the start of a recording.
///
/// The budget is deliberately tiny: the answer is a banner, and a recording
/// that has already begun must never wait on it.
public struct HealthClient: Sendable {
    public static let defaultTimeout: TimeInterval = 2

    private let session: URLSession
    private let timeout: TimeInterval

    /// - Parameter session: injectable so tests can drive a `URLProtocol` stub.
    public init(
        session: URLSession = HealthClient.makeSession(),
        timeout: TimeInterval = HealthClient.defaultTimeout
    ) {
        self.session = session
        self.timeout = timeout
    }

    public static func makeSession(timeout: TimeInterval = defaultTimeout) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    public func makeRequest(config: EndpointConfig) -> URLRequest {
        var request = URLRequest(url: config.url)
        request.httpMethod = "GET"
        request.setValue(config.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        // A cached "ready" from a host that has since died would be worse than
        // no answer at all.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return request
    }

    public func check(config: EndpointConfig) async -> HealthStatus {
        do {
            let (data, response) = try await session.data(for: makeRequest(config: config))
            return Self.status(data: data, response: response)
        } catch {
            return .unreachable(kind: DictationFailureKind(error: error))
        }
    }

    static func status(data: Data, response: URLResponse) -> HealthStatus {
        guard let http = response as? HTTPURLResponse else {
            return .unreachable(kind: .transport("no HTTP response"))
        }
        let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
        switch http.statusCode {
        case 200..<300: return .ready
        case 401: return .unauthorized(serverMessage: message)
        case 503: return .notReady(serverMessage: message)
        default: return .unexpected(status: http.statusCode, serverMessage: message)
        }
    }
}
