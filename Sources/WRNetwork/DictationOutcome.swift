import Foundation

/// What the host did with the audio, from the `X-WhisperRocket-Mode` header.
public enum DictationMode: String, Equatable, Sendable, CaseIterable {
    /// Straight transcription.
    case transcript
    /// A trigger phrase turned the dictation into a composed answer.
    case compose

    /// Unknown or missing values read as `.transcript`: the host only tags the
    /// exceptional mode, and a header we do not recognise must not lose text.
    public init(headerValue: String?) {
        let raw = headerValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = raw.flatMap(DictationMode.init(rawValue:)) ?? .transcript
    }
}

/// Why an upload produced no text.
///
/// Richer than WRCore's `DictationFailure` on purpose: the retry policy only
/// cares that nothing answered, while the panel wants to say *whether the host
/// refused the connection or simply took too long*. ``httpStatus`` and
/// ``isCancellation`` are the two primitives the orchestrator bridges on.
public enum DictationFailureKind: Equatable, Hashable, Sendable {
    /// 400 — the host rejected the request shape.
    case badRequest
    /// 401 — the token is wrong or missing.
    case unauthorized
    /// 404 — wrong path, or a host that is not WhisperRocket.
    case notFound
    /// 413 — the audio exceeded the host's 25 MB ceiling.
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

    /// The request ran out of time.
    case timedOut
    /// DNS, refused connection, a dropped socket — the host is not there.
    case cannotConnect
    /// We cancelled the upload.
    case cancelled
    /// The audio file is gone or unreadable — nothing to send, and no later
    /// attempt will change that.
    case audioUnreadable(String)
    /// Any other transport failure, with the system's description.
    case transport(String)

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

    public init(error: Error) {
        guard let urlError = error as? URLError else {
            self = .transport(error.localizedDescription)
            return
        }
        switch urlError.code {
        case .timedOut:
            self = .timedOut
        case .cancelled:
            self = .cancelled
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .notConnectedToInternet, .networkConnectionLost, .secureConnectionFailed:
            // The host answers HTTP/1.0 and closes every connection, so a
            // reused socket can die under us; that is a retryable transport
            // failure, not a dead host.
            self = .cannotConnect
        case .fileDoesNotExist, .fileIsDirectory, .noPermissionsToReadFile, .zeroByteResource:
            self = .audioUnreadable(urlError.localizedDescription)
        default:
            self = .transport(urlError.localizedDescription)
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
        case .timedOut, .cannotConnect, .cancelled, .audioUnreadable, .transport: nil
        }
    }

    public var isCancellation: Bool { self == .cancelled }

    public var isAudioUnreadable: Bool {
        if case .audioUnreadable = self { return true }
        return false
    }
}

/// The result of one dictation upload.
public enum DictationOutcome: Equatable, Sendable {
    /// `text` is the host's body verbatim — no trimming, so nothing the user
    /// dictated is silently dropped. An empty `text` means the host answered
    /// 2xx with nothing in it; the caller decides what to show.
    case success(text: String, mode: DictationMode, enhanced: Bool)
    /// `serverMessage` is the host's plain-text error body, kept so the panel
    /// can show (and VoiceOver can read) what the host actually said.
    case failure(kind: DictationFailureKind, serverMessage: String?)

    public var text: String? {
        if case .success(let text, _, _) = self { return text }
        return nil
    }

    public var failureKind: DictationFailureKind? {
        if case .failure(let kind, _) = self { return kind }
        return nil
    }
}
