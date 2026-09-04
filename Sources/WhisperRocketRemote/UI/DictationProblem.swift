import Foundation
import WRCore
import WRNetwork

/// A failure, already turned into words a person can act on.
///
/// The translation from `DictationFailureKind` lives here rather than in the
/// orchestrator so there is exactly one place where a status code becomes a
/// sentence — and so the panel can be exercised against every branch without a
/// network stack. The orchestrator only has to hand over what the network
/// layer already produced: `init(kind:serverMessage:)`.
nonisolated struct DictationProblem: Equatable, Sendable {
    /// Short, headline-sized: "Wrong token", not "HTTP 401".
    var title: String
    /// One sentence saying what happened and, where it helps, what to do.
    var detail: String
    /// The host's own plain-text error body, shown verbatim underneath. Kept
    /// because the host often knows more than the status code does.
    var hostMessage: String?
    /// Whether sending the same audio again could plausibly work.
    var isRetryable: Bool

    init(title: String, detail: String, hostMessage: String? = nil, isRetryable: Bool) {
        self.title = title
        self.detail = detail
        self.hostMessage = hostMessage
        self.isRetryable = isRetryable
    }

    init(kind: DictationFailureKind, serverMessage: String? = nil) {
        // The retry verdict is WRCore's, not a second opinion: bridged through
        // the two primitives DictationOutcome documents.
        let coreFailure: DictationFailure = if let status = kind.httpStatus {
            DictationFailure(httpStatus: status)
        } else if kind.isCancellation {
            .cancelled
        } else if kind.isAudioUnreadable {
            .audioUnreadable
        } else {
            .network
        }

        let title: String
        let detail: String
        switch kind {
        case .badRequest:
            title = L.errorTitleGeneric
            detail = L.errorBadRequest
        case .unauthorized:
            title = L.errorTitleToken
            detail = L.errorUnauthorized
        case .notFound:
            title = L.errorTitleUnreachable
            detail = L.errorNotFound
        case .payloadTooLarge:
            title = L.errorTitleTooLarge
            detail = L.errorPayloadTooLarge
        case .unprocessable:
            title = L.errorTitleNoSpeech
            detail = L.errorUnprocessable
        case .rateLimited:
            title = L.errorTitleBusy
            detail = L.errorRateLimited
        case .serverError:
            title = L.errorTitleGeneric
            detail = L.errorServerError
        case .serviceUnavailable:
            title = L.errorTitleLoading
            detail = L.errorServiceUnavailable
        case .unexpectedStatus(let code):
            title = L.errorTitleGeneric
            detail = L.errorUnexpectedStatus(code)
        case .timedOut:
            title = L.errorTitleUnreachable
            detail = L.errorTimedOut
        case .cannotConnect:
            title = L.errorTitleUnreachable
            detail = L.errorCannotConnect
        case .cancelled:
            title = L.errorTitleGeneric
            detail = L.errorCancelled
        case .audioUnreadable(let message):
            title = L.errorTitleGeneric
            detail = L.errorAudioUnreadable(message)
        case .transport(let message):
            title = L.errorTitleUnreachable
            detail = L.errorTransport(message)
        }

        self.init(
            title: title,
            detail: detail,
            hostMessage: Self.trimmed(serverMessage),
            isRetryable: UploadPlan.isRetryable(coreFailure)
        )
    }

    /// An empty or whitespace-only body is not a message; showing it would add
    /// a blank quote block under every failure.
    private static func trimmed(_ message: String?) -> String? {
        guard let message else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
