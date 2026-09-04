import Foundation

/// Everything the network module is allowed to know: one URL and one token.
///
/// WRNetwork imports nothing but Foundation, so it cannot see `HostConfig` —
/// which is the point. Code that touches the wire cannot reach the settings or
/// the recording store. The orchestrator hands over the two fields it needs:
///
/// ```swift
/// EndpointConfig(url: hostConfig.dictateURL, token: hostConfig.token)
/// ```
public struct EndpointConfig: Equatable, Hashable, Sendable {
    public let url: URL
    public let token: String

    public init(url: URL, token: String) {
        self.url = url
        self.token = token
    }

    var authorizationHeader: String { "Bearer \(token)" }
}
