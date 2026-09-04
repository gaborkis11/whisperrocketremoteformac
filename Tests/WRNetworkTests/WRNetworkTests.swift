import Testing
@testable import WRNetwork

@Test func buildsEndpointURL() {
    let url = WRNetwork.endpointURL(host: "100.64.0.42", port: 8771, path: "/health")
    #expect(url?.absoluteString == "http://100.64.0.42:8771/health")
}
