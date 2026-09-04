import Foundation
import Testing

/// `URLProtocol` state is process-global, so every suite that drives the mock
/// hangs off this one — `.serialized` applies to all descendants, which keeps
/// the sibling suites from stepping on each other's stub.
@Suite(.serialized)
enum NetworkSuite {}

/// Records what the clients actually put on the wire and replays a canned
/// answer.
final class MockURLProtocol: URLProtocol {
    struct Captured: Sendable {
        var request: URLRequest
        /// The upload body, drained from the request's stream.
        var body: Data
    }

    struct Stub: Sendable {
        var statusCode: Int
        var headers: [String: String]
        var body: Data
        var httpVersion: String

        init(statusCode: Int = 200, headers: [String: String] = [:], body: Data = Data(), httpVersion: String = "HTTP/1.0") {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
            self.httpVersion = httpVersion
        }

        static func text(_ text: String, statusCode: Int = 200, headers: [String: String] = [:]) -> Stub {
            Stub(statusCode: statusCode, headers: headers, body: Data(text.utf8))
        }
    }

    enum Outcome: Sendable {
        case stub(Stub)
        case failure(URLError.Code)
    }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var outcome: Outcome = .stub(Stub())
        private var captured: [Captured] = []

        func set(_ outcome: Outcome) {
            lock.withLock {
                self.outcome = outcome
                self.captured = []
            }
        }

        func take() -> Outcome { lock.withLock { outcome } }
        func record(_ item: Captured) { lock.withLock { captured.append(item) } }
        var requests: [Captured] { lock.withLock { captured } }
    }

    private static let state = State()

    static func reset(with outcome: Outcome) { state.set(outcome) }
    static var captured: [Captured] { state.requests }
    static var lastRequest: Captured? { state.requests.last }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.state.record(Captured(request: request, body: Self.drainBody(of: request)))

        switch Self.state.take() {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .stub(let stub):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: stub.statusCode,
                httpVersion: stub.httpVersion,
                headerFields: stub.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    /// `upload(fromFile:)` reaches the protocol as a body stream, never as
    /// `httpBody`, so the bytes have to be read out of the stream.
    private static func drainBody(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(contentsOf: buffer[0..<read])
        }
        return data
    }
}
