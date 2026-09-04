import Foundation
import Testing
@testable import WRCore

@Suite struct HostConfigTests {
    @Test func buildsBothEndpointsFromHostAndPort() throws {
        let config = try HostConfig(host: "100.64.0.42", port: 8771, token: "abc")

        #expect(config.dictateURL.absoluteString == "http://100.64.0.42:8771/dictate")
        #expect(config.healthURL.absoluteString == "http://100.64.0.42:8771/health")
        #expect(config.hasToken)
    }

    @Test func theHostsRealPortIsTheDefault() throws {
        let config = try HostConfig(host: "example.local", token: "abc")
        #expect(config.port == 8771)
        #expect(config.dictateURL.absoluteString == "http://example.local:8771/dictate")
    }

    @Test func aPastedURLKeepsItsSchemeAndLosesItsDecoration() throws {
        #expect(try HostConfig(host: "  http://example.local/  ", token: "t").host == "example.local")
        #expect(try HostConfig(host: "http://example.local", token: "t").scheme == .http)

        // Downgrading a pasted https host to http would be a silent security
        // change, so the scheme is honoured.
        let secure = try HostConfig(host: "HTTPS://example.local", token: "t")
        #expect(secure.scheme == .https)
        #expect(secure.dictateURL.absoluteString == "https://example.local:8771/dictate")
    }

    @Test func anEmptyHostIsRejected() {
        #expect(throws: HostConfigError.emptyHost) { try HostConfig(host: "", token: "t") }
        #expect(throws: HostConfigError.emptyHost) { try HostConfig(host: "   ", token: "t") }
        #expect(throws: HostConfigError.emptyHost) { try HostConfig(host: "http://", token: "t") }
    }

    @Test(arguments: [0, -1, 65536, 100_000])
    func portsOutsideTheValidRangeAreRejected(port: Int) {
        #expect(throws: HostConfigError.portOutOfRange(port)) {
            try HostConfig(host: "example.local", port: port, token: "t")
        }
    }

    @Test(arguments: [1, 80, 8771, 65535])
    func theWholeValidPortRangeIsAccepted(port: Int) throws {
        #expect(try HostConfig(host: "example.local", port: port, token: "t").port == port)
    }

    @Test(arguments: [
        "example .local",          // whitespace inside
        "example.local:8771",      // a port belongs in the port field
        "example.local/dictate",   // a path is not a host
        "user@example.local",      // credentials
        "exa\u{0000}mple",         // control character
    ])
    func textThatIsNotABareHostIsRejected(host: String) {
        #expect(throws: HostConfigError.self) { try HostConfig(host: host, token: "t") }
    }

    @Test func bracketedIPv6LiteralsWork() throws {
        let config = try HostConfig(host: "[fd7a:115c::1]", port: 8771, token: "t")
        #expect(config.healthURL.absoluteString == "http://[fd7a:115c::1]:8771/health")
    }

    @Test func anEmptyTokenIsStoredButFlagged() throws {
        let config = try HostConfig(host: "example.local", token: "   ")
        #expect(!config.hasToken)
        #expect(try HostConfig(host: "example.local", token: "t").hasToken)
    }

    @Test func codableRoundTripKeepsEveryField() throws {
        let config = try HostConfig(host: "100.64.0.42", port: 8771, token: "abc", scheme: .https)
        let decoded = try JSONDecoder().decode(HostConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
        #expect(decoded.dictateURL == config.dictateURL)
    }

    @Test func decodingRevalidatesSoAHandEditedSettingCannotSmuggleInABadURL() throws {
        let json = Data(#"{"host":"exa mple","port":8771,"token":"t","scheme":"http"}"#.utf8)
        #expect(throws: HostConfigError.self) {
            try JSONDecoder().decode(HostConfig.self, from: json)
        }
    }

    @Test func decodingToleratesAnIndexWithoutASchemeOrToken() throws {
        let json = Data(#"{"host":"example.local","port":8771}"#.utf8)
        let config = try JSONDecoder().decode(HostConfig.self, from: json)
        #expect(config.scheme == .http)
        #expect(!config.hasToken)
    }
}
