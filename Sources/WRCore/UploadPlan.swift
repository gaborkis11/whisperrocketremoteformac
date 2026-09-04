import Foundation

/// Why a dictation upload did not produce text.
///
/// This is WRCore's vocabulary for retry decisions. WRNetwork owns a parallel,
/// richer `DictationFailureKind` (it also separates timeout from refused
/// connection for the UI) and cannot reference this type, because both modules
/// are Foundation-only by design. The orchestrator bridges the two with the
/// two primitives that fully determine the policy — an HTTP status, or the
/// absence of one:
///
/// ```swift
/// let failure: DictationFailure = if let status = kind.httpStatus {
///     DictationFailure(httpStatus: status)
/// } else if kind.isCancellation {
///     .cancelled
/// } else if kind.isAudioUnreadable {
///     .audioUnreadable
/// } else {
///     .network
/// }
/// ```
public enum DictationFailure: Equatable, Hashable, Sendable {
    /// 400 — the host rejected the request shape.
    case badRequest
    /// 401 — the token is wrong or missing.
    case unauthorized
    /// 404 — wrong path or a host that is not WhisperRocket.
    case notFound
    /// 413 — the audio exceeded the host's `DEFAULT_MAX_BYTES` (25 MB).
    case payloadTooLarge
    /// 422 — the host processed the audio and found no speech.
    case unprocessable
    /// 429 — the host is already busy with another dictation.
    case rateLimited
    /// 500 — the host blew up mid-transcription.
    case serverError
    /// 503 — the host is up but the model is still loading.
    case serviceUnavailable
    /// Any other status the host answered with.
    case unexpectedStatus(Int)
    /// No HTTP answer at all: timeout, refused connection, dropped socket.
    case network
    /// The upload was cancelled from our side.
    case cancelled
    /// The audio file is gone or unreadable — there is nothing left to send.
    case audioUnreadable

    /// Total mapping from an answered HTTP status.
    public init(httpStatus: Int) {
        switch httpStatus {
        case 400: self = .badRequest
        case 401: self = .unauthorized
        case 404: self = .notFound
        case 413: self = .payloadTooLarge
        case 422: self = .unprocessable
        case 429: self = .rateLimited
        case 500: self = .serverError
        case 503: self = .serviceUnavailable
        default: self = .unexpectedStatus(httpStatus)
        }
    }

    /// The status the host answered with, or `nil` when nothing answered.
    public var httpStatus: Int? {
        switch self {
        case .badRequest: 400
        case .unauthorized: 401
        case .notFound: 404
        case .payloadTooLarge: 413
        case .unprocessable: 422
        case .rateLimited: 429
        case .serverError: 500
        case .serviceUnavailable: 503
        case .unexpectedStatus(let code): code
        case .network, .cancelled, .audioUnreadable: nil
        }
    }
}

/// The retry policy for one recording's upload — a pure function of the
/// attempt number and the failure, so the orchestrator's loop holds no policy.
public enum UploadPlan {
    /// Pauses between attempts. Total attempts = `backoff.count + 1`.
    public static let backoff: [Duration] = [.seconds(2), .seconds(5)]

    public static var maxAttempts: Int { backoff.count + 1 }

    /// Retry only what a later attempt could plausibly fix: a transport
    /// failure, a busy host (429), a loading model (503), a crashed request
    /// (500). A rejected token, an oversized file or speechless audio will
    /// fail identically forever, so they end the upload immediately.
    public static func isRetryable(_ failure: DictationFailure) -> Bool {
        switch failure {
        case .network, .rateLimited, .serverError, .serviceUnavailable:
            true
        case .badRequest, .unauthorized, .notFound, .payloadTooLarge, .unprocessable,
             .cancelled, .audioUnreadable:
            false
        case .unexpectedStatus(let code):
            // Unknown 5xx (a proxy's 502/504) is transient; unknown 4xx is not.
            (500...599).contains(code)
        }
    }

    /// How long to wait before the next attempt, or `nil` when the upload is
    /// finished — either the failure is permanent or `attempt` was the last one.
    ///
    /// - Parameter attempt: 1-based number of the attempt that just failed.
    public static func retryDelay(attempt: Int, failure: DictationFailure) -> Duration? {
        guard attempt >= 1, attempt < maxAttempts, isRetryable(failure) else { return nil }
        return backoff[attempt - 1]
    }
}
