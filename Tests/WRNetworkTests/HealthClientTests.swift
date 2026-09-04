import Foundation
import Testing
@testable import WRNetwork

extension NetworkSuite {
    @Suite struct HealthClientTests {
        private let endpoint = EndpointConfig(
            url: URL(string: "http://100.64.0.42:8771/health")!,
            token: "s3cret-token"
        )

        private func client() -> HealthClient {
            HealthClient(session: MockURLProtocol.makeSession())
        }

        @Test func probeIsAGetWithBearerAndATwoSecondBudget() async throws {
            MockURLProtocol.reset(with: .stub(.text("ok")))

            _ = await client().check(config: endpoint)

            let captured = try #require(MockURLProtocol.lastRequest)
            #expect(captured.request.url?.absoluteString == "http://100.64.0.42:8771/health")
            #expect(captured.request.httpMethod == "GET")
            #expect(captured.request.value(forHTTPHeaderField: "Authorization") == "Bearer s3cret-token")
            #expect(captured.request.timeoutInterval == 2)
            #expect(captured.body.isEmpty)
        }

        @Test func defaultSessionKeepsTheProbeShort() {
            let session = HealthClient.makeSession()
            #expect(session.configuration.timeoutIntervalForRequest == 2)
            #expect(session.configuration.timeoutIntervalForResource == 2)
        }

        @Test func twoHundredIsReady() async {
            MockURLProtocol.reset(with: .stub(.text("ok")))
            #expect(await client().check(config: endpoint) == .ready)
        }

        @Test func fiveOhThreeIsNotReadyAndKeepsTheHostsWording() async {
            MockURLProtocol.reset(with: .stub(.text("model loading\n", statusCode: 503)))
            #expect(await client().check(config: endpoint) == .notReady(serverMessage: "model loading"))
        }

        @Test func fourOhOneIsItsOwnCaseSoThePanelCanSayBadToken() async {
            MockURLProtocol.reset(with: .stub(.text("unauthorized", statusCode: 401)))
            #expect(await client().check(config: endpoint) == .unauthorized(serverMessage: "unauthorized"))
        }

        @Test func otherStatusesArriveWithTheirCode() async {
            MockURLProtocol.reset(with: .stub(.text("", statusCode: 500)))
            #expect(await client().check(config: endpoint) == .unexpected(status: 500, serverMessage: nil))
        }

        @Test(arguments: [URLError.Code.timedOut, .cannotConnectToHost, .notConnectedToInternet])
        func transportFailuresAreUnreachable(code: URLError.Code) async {
            MockURLProtocol.reset(with: .failure(code))

            let status = await client().check(config: endpoint)

            #expect(!status.isReachable)
            #expect(!status.isReady)
        }

        @Test func onlyReadyFeedsRecorderStateAsReachable() {
            #expect(HealthStatus.ready.isReady)
            #expect(!HealthStatus.notReady(serverMessage: nil).isReady)
            #expect(!HealthStatus.unauthorized(serverMessage: nil).isReady)
            #expect(!HealthStatus.unexpected(status: 500, serverMessage: nil).isReady)
            #expect(!HealthStatus.unreachable(kind: .timedOut).isReady)

            // A host that answered at all is reachable, even when it says no.
            #expect(HealthStatus.notReady(serverMessage: nil).isReachable)
            #expect(HealthStatus.unauthorized(serverMessage: nil).isReachable)
            #expect(!HealthStatus.unreachable(kind: .cannotConnect).isReachable)
        }
    }
}
