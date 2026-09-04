import Foundation
import Testing
@testable import WRNetwork

extension NetworkSuite {
    @Suite struct DictationClientTests {
        private let endpoint = EndpointConfig(
            url: URL(string: "http://100.64.0.42:8771/dictate")!,
            token: "s3cret-token"
        )

        private func makeAudioFile(_ bytes: [UInt8], name: String = "clip.m4a") throws -> URL {
            let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            try Data(bytes).write(to: url)
            return url
        }

        private func client() -> DictationClient {
            DictationClient(session: MockURLProtocol.makeSession())
        }

        // MARK: - Request shape

        @Test func uploadsRawFileBytesWithBearerAndAudioContentType() async throws {
            // Enough bytes to prove the body is streamed whole, not a prefix.
            let bytes = (0..<9000).map { UInt8($0 % 251) }
            let fileURL = try makeAudioFile(bytes)
            MockURLProtocol.reset(with: .stub(.text("szia")))

            _ = await client().send(fileURL: fileURL, config: endpoint)

            let captured = try #require(MockURLProtocol.lastRequest)
            #expect(captured.request.url?.absoluteString == "http://100.64.0.42:8771/dictate")
            #expect(captured.request.httpMethod == "POST")
            #expect(captured.request.value(forHTTPHeaderField: "Authorization") == "Bearer s3cret-token")
            #expect(captured.request.value(forHTTPHeaderField: "Content-Type") == "audio/mp4")
            // Raw body, not multipart: byte-for-byte the file, no boundary wrapper.
            #expect(captured.body == Data(bytes))
        }

        @Test func requestCarriesTheConfiguredTimeout() {
            let request = DictationClient(session: MockURLProtocol.makeSession()).makeRequest(config: endpoint)
            #expect(request.timeoutInterval == 120)
        }

        @Test func defaultSessionUsesTheHostFriendlyTimeouts() {
            let session = DictationClient.makeSession()
            #expect(session.configuration.timeoutIntervalForRequest == 120)
            #expect(session.configuration.timeoutIntervalForResource == 300)
            #expect(session.configuration.waitsForConnectivity == false)
        }

        // MARK: - Response reading

        @Test func successCarriesTextModeAndEnhancedFlag() async throws {
            let fileURL = try makeAudioFile([1, 2, 3])
            MockURLProtocol.reset(with: .stub(.text(
                "Ez a fogalmazott válasz.",
                headers: ["X-WhisperRocket-Mode": "compose", "X-WhisperRocket-Enhanced": "true"]
            )))

            let outcome = await client().send(fileURL: fileURL, config: endpoint)

            #expect(outcome == .success(text: "Ez a fogalmazott válasz.", mode: .compose, enhanced: true))
        }

        @Test func missingHeadersFallBackToPlainTranscript() async throws {
            let fileURL = try makeAudioFile([1])
            MockURLProtocol.reset(with: .stub(.text("sima átirat")))

            let outcome = await client().send(fileURL: fileURL, config: endpoint)

            #expect(outcome == .success(text: "sima átirat", mode: .transcript, enhanced: false))
        }

        @Test(arguments: [
            ("transcript", DictationMode.transcript),
            ("compose", .compose),
            ("COMPOSE", .compose),
            (" compose ", .compose),
            ("something-new", .transcript),
        ])
        func modeHeaderParsing(value: String, expected: DictationMode) {
            #expect(DictationMode(headerValue: value) == expected)
        }

        @Test(arguments: [
            ("true", true), ("TRUE", true), ("1", true), ("yes", true), ("on", true),
            ("false", false), ("0", false), ("no", false), ("", false),
        ])
        func enhancedHeaderParsing(value: String, expected: Bool) {
            #expect(DictationClient.parseBool(value) == expected)
        }

        @Test func absentEnhancedHeaderIsFalse() {
            #expect(DictationClient.parseBool(nil) == false)
        }

        @Test func headerLookupIsCaseInsensitive() async throws {
            let fileURL = try makeAudioFile([1])
            MockURLProtocol.reset(with: .stub(.text(
                "x",
                headers: ["x-whisperrocket-mode": "compose", "x-whisperrocket-enhanced": "1"]
            )))

            let outcome = await client().send(fileURL: fileURL, config: endpoint)

            #expect(outcome == .success(text: "x", mode: .compose, enhanced: true))
        }

        @Test func successTextIsPreservedVerbatim() async throws {
            let fileURL = try makeAudioFile([1])
            MockURLProtocol.reset(with: .stub(.text("  szöveg\n")))

            let outcome = await client().send(fileURL: fileURL, config: endpoint)

            #expect(outcome.text == "  szöveg\n")
        }

        // MARK: - Failures

        @Test(arguments: [
            (400, DictationFailureKind.badRequest),
            (401, .unauthorized),
            (404, .notFound),
            (413, .payloadTooLarge),
            (422, .unprocessable),
            (429, .rateLimited),
            (500, .serverError),
            (503, .serviceUnavailable),
            (418, .unexpectedStatus(418)),
            (502, .unexpectedStatus(502)),
        ])
        func statusMapsToKind(status: Int, expected: DictationFailureKind) async throws {
            let fileURL = try makeAudioFile([1])
            MockURLProtocol.reset(with: .stub(.text("nope", statusCode: status)))

            let outcome = await client().send(fileURL: fileURL, config: endpoint)

            #expect(outcome == .failure(kind: expected, serverMessage: "nope"))
        }

        @Test func plainTextServerMessageIsKept() async throws {
            let fileURL = try makeAudioFile([1])
            MockURLProtocol.reset(with: .stub(.text("\nNem hallottam beszédet.\n", statusCode: 422)))

            let outcome = await client().send(fileURL: fileURL, config: endpoint)

            #expect(outcome == .failure(kind: .unprocessable, serverMessage: "Nem hallottam beszédet."))
        }

        @Test func emptyErrorBodyYieldsNoServerMessage() async throws {
            let fileURL = try makeAudioFile([1])
            MockURLProtocol.reset(with: .stub(.text("   ", statusCode: 500)))

            let outcome = await client().send(fileURL: fileURL, config: endpoint)

            #expect(outcome == .failure(kind: .serverError, serverMessage: nil))
        }

        @Test(arguments: [
            (URLError.Code.timedOut, DictationFailureKind.timedOut),
            (.cannotConnectToHost, .cannotConnect),
            (.cannotFindHost, .cannotConnect),
            (.networkConnectionLost, .cannotConnect),
            (.notConnectedToInternet, .cannotConnect),
            (.cancelled, .cancelled),
        ])
        func transportErrorsMapToKind(code: URLError.Code, expected: DictationFailureKind) async throws {
            let fileURL = try makeAudioFile([1])
            MockURLProtocol.reset(with: .failure(code))

            let outcome = await client().send(fileURL: fileURL, config: endpoint)

            #expect(outcome == .failure(kind: expected, serverMessage: nil))
        }

        @Test func unknownTransportErrorKeepsItsDescription() {
            let kind = DictationFailureKind(error: URLError(.badServerResponse))
            guard case .transport(let description) = kind else {
                Issue.record("expected .transport, got \(kind)")
                return
            }
            #expect(!description.isEmpty)
        }

        @Test func aMissingFileNeverBecomesASilentlyEmptyUpload() async {
            MockURLProtocol.reset(with: .stub(.text("unused")))
            let missing = URL.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")

            let outcome = await client().send(fileURL: missing, config: endpoint)

            #expect(outcome.failureKind?.isAudioUnreadable == true)
            #expect(outcome.text == nil)
            // Nothing was even attempted.
            #expect(MockURLProtocol.captured.isEmpty)
        }

        // MARK: - The bridge WRCore's retry policy is built on

        @Test func httpStatusRoundTripsThroughTheKind() {
            for status in [400, 401, 404, 413, 422, 429, 500, 503, 418] {
                #expect(DictationFailureKind(httpStatus: status).httpStatus == status)
            }
        }

        @Test func transportKindsCarryNoHTTPStatus() {
            let kinds: [DictationFailureKind] = [
                .timedOut, .cannotConnect, .cancelled, .audioUnreadable("clip.m4a"), .transport("x"),
            ]
            for kind in kinds {
                #expect(kind.httpStatus == nil)
            }
            #expect(DictationFailureKind.cancelled.isCancellation)
            #expect(!DictationFailureKind.timedOut.isCancellation)
            #expect(DictationFailureKind.audioUnreadable("x").isAudioUnreadable)
            #expect(!DictationFailureKind.cannotConnect.isAudioUnreadable)
        }
    }
}
