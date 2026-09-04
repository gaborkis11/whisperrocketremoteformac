import Testing
@testable import WRCore

@Suite struct UploadPlanTests {
    static let retryable: [DictationFailure] = [
        .network, .rateLimited, .serverError, .serviceUnavailable, .unexpectedStatus(502),
    ]
    static let permanent: [DictationFailure] = [
        .unauthorized, .payloadTooLarge, .unprocessable, .badRequest, .notFound,
        .cancelled, .audioUnreadable, .unexpectedStatus(418),
    ]

    @Test func threeAttemptsInTotalWithTwoAndFiveSecondPauses() {
        #expect(UploadPlan.maxAttempts == 3)
        #expect(UploadPlan.backoff == [.seconds(2), .seconds(5)])
    }

    @Test(arguments: retryable)
    func aRetryableFailureWaitsTwoThenFiveSecondsAndThenGivesUp(failure: DictationFailure) {
        #expect(UploadPlan.isRetryable(failure))
        #expect(UploadPlan.retryDelay(attempt: 1, failure: failure) == .seconds(2))
        #expect(UploadPlan.retryDelay(attempt: 2, failure: failure) == .seconds(5))
        // The third attempt was the last one the plan allows.
        #expect(UploadPlan.retryDelay(attempt: 3, failure: failure) == nil)
        #expect(UploadPlan.retryDelay(attempt: 4, failure: failure) == nil)
    }

    @Test(arguments: permanent)
    func aPermanentFailureStopsOnTheFirstAttempt(failure: DictationFailure) {
        #expect(!UploadPlan.isRetryable(failure))
        for attempt in 1...3 {
            #expect(UploadPlan.retryDelay(attempt: attempt, failure: failure) == nil)
        }
    }

    @Test func theTokenAndPayloadFailuresNeverRetry() {
        // Called out explicitly: these are the ones a retry loop would burn
        // the user's time on for nothing.
        #expect(UploadPlan.retryDelay(attempt: 1, failure: .unauthorized) == nil)
        #expect(UploadPlan.retryDelay(attempt: 1, failure: .payloadTooLarge) == nil)
        #expect(UploadPlan.retryDelay(attempt: 1, failure: .unprocessable) == nil)
    }

    @Test func attemptNumbersBelowOneAreRefused() {
        #expect(UploadPlan.retryDelay(attempt: 0, failure: .network) == nil)
        #expect(UploadPlan.retryDelay(attempt: -1, failure: .network) == nil)
    }

    @Test func unknownServerSideStatusesRetryAndUnknownClientSideOnesDoNot() {
        #expect(UploadPlan.isRetryable(.unexpectedStatus(500)))
        #expect(UploadPlan.isRetryable(.unexpectedStatus(504)))
        #expect(UploadPlan.isRetryable(.unexpectedStatus(599)))
        #expect(!UploadPlan.isRetryable(.unexpectedStatus(499)))
        #expect(!UploadPlan.isRetryable(.unexpectedStatus(403)))
        #expect(!UploadPlan.isRetryable(.unexpectedStatus(200)))
    }

    // MARK: - The bridge from WRNetwork

    @Test(arguments: [
        (400, DictationFailure.badRequest),
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
    func statusesMapToTheSameFailuresWRNetworkReports(status: Int, expected: DictationFailure) {
        #expect(DictationFailure(httpStatus: status) == expected)
        #expect(expected.httpStatus == status)
    }

    @Test func failuresWithoutAnAnswerCarryNoStatus() {
        #expect(DictationFailure.network.httpStatus == nil)
        #expect(DictationFailure.cancelled.httpStatus == nil)
        #expect(DictationFailure.audioUnreadable.httpStatus == nil)
    }
}
