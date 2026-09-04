import Foundation

public enum HostScheme: String, Codable, Equatable, Sendable, CaseIterable {
    case http
    case https
}

public enum HostConfigError: Error, Equatable, Sendable {
    case emptyHost
    /// The text cannot be a bare host: it carries a port, a path, credentials,
    /// whitespace or characters a URL host cannot hold.
    case invalidHost(String)
    case portOutOfRange(Int)
}

/// Where the dictation host lives, validated once so the endpoints below are
/// non-optional for everyone downstream.
public struct HostConfig: Equatable, Sendable, Codable {
    public static let defaultPort = 8771
    public static let dictatePath = "/dictate"
    public static let healthPath = "/health"
    public static let portRange = 1...65535

    public let scheme: HostScheme
    /// Normalised: trimmed, scheme and trailing slashes stripped.
    public let host: String
    public let port: Int
    public let token: String

    public let dictateURL: URL
    public let healthURL: URL

    public var hasToken: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// - Parameter host: a bare host name or IP. A pasted `http(s)://` prefix
    ///   is honoured (an https paste must not be silently downgraded) and
    ///   trailing slashes are dropped; anything else that is not a host is
    ///   rejected rather than guessed at. IPv6 literals need their brackets.
    public init(host: String, port: Int = defaultPort, token: String, scheme: HostScheme = .http) throws {
        var text = host.trimmingCharacters(in: .whitespacesAndNewlines)
        var scheme = scheme

        for candidate in HostScheme.allCases {
            let prefix = "\(candidate.rawValue)://"
            if text.lowercased().hasPrefix(prefix) {
                scheme = candidate
                text = String(text.dropFirst(prefix.count))
                break
            }
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }

        guard !text.isEmpty else { throw HostConfigError.emptyHost }
        guard Self.portRange.contains(port) else { throw HostConfigError.portOutOfRange(port) }

        var components = URLComponents()
        components.scheme = scheme.rawValue
        components.port = port
        // An IPv6 literal keeps its brackets — that is the form URLComponents
        // accepts and the only one that yields a usable URL.
        components.host = text

        // The setter percent-encodes whatever it is handed and refuses to build
        // a URL from a host that is not one, so this round-trip is what
        // actually separates a host from a pasted URL fragment.
        guard components.percentEncodedHost == text, components.url != nil else {
            throw HostConfigError.invalidHost(text)
        }

        self.scheme = scheme
        self.host = text
        self.port = port
        self.token = token

        components.path = Self.dictatePath
        guard let dictateURL = components.url else { throw HostConfigError.invalidHost(text) }
        components.path = Self.healthPath
        guard let healthURL = components.url else { throw HostConfigError.invalidHost(text) }
        self.dictateURL = dictateURL
        self.healthURL = healthURL
    }

    // Only the inputs are stored; the endpoints are re-derived (and re-validated)
    // on the way back in, so a hand-edited defaults entry cannot smuggle in a
    // bogus URL.
    private enum CodingKeys: String, CodingKey {
        case scheme, host, port, token
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            host: container.decode(String.self, forKey: .host),
            port: container.decode(Int.self, forKey: .port),
            token: container.decodeIfPresent(String.self, forKey: .token) ?? "",
            scheme: try container.decodeIfPresent(HostScheme.self, forKey: .scheme) ?? .http
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scheme, forKey: .scheme)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(token, forKey: .token)
    }
}
