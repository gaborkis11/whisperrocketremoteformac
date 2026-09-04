import Foundation
import WRCore
import WRNetwork

// The `WRCore`/`WRNetwork` *enums* in each module's SmokeTest shadow the module
// names, so nothing here can be written qualified.
//
// WRCore and WRNetwork are both Foundation-only and cannot see each other, so
// the two failure vocabularies meet here — in the app, the only place that
// imports both. The recipe is the one written into `WRCore.DictationFailure`'s
// documentation: an HTTP status, or the absence of one, fully determines the
// retry policy.
extension DictationFailure {
    init(kind: DictationFailureKind) {
        if let status = kind.httpStatus {
            self.init(httpStatus: status)
        } else if kind.isCancellation {
            self = .cancelled
        } else if kind.isAudioUnreadable {
            self = .audioUnreadable
        } else {
            self = .network
        }
    }
}

extension DictationFailureKind {
    /// One line, in English, for the panel and the logs. F4 localises.
    var message: String {
        switch self {
        case .badRequest: "The host rejected the request."
        case .unauthorized: "Wrong or missing token."
        case .notFound: "No /dictate endpoint at that address."
        case .payloadTooLarge: "The recording is larger than the host accepts."
        case .unprocessable: "The host found no speech in the recording."
        case .rateLimited: "The host is busy with another dictation."
        case .serverError: "The host failed while transcribing."
        case .serviceUnavailable: "The host is still loading its model."
        case .unexpectedStatus(let code): "The host answered with HTTP \(code)."
        case .timedOut: "The host did not answer in time."
        case .cannotConnect: "The host could not be reached."
        case .cancelled: "The upload was cancelled."
        case .audioUnreadable(let detail): "The recording could not be read: \(detail)"
        case .transport(let detail): "Network error: \(detail)"
        }
    }

    /// Short, stable identifier for log lines and probe assertions.
    var label: String {
        switch self {
        case .badRequest: "badRequest"
        case .unauthorized: "unauthorized"
        case .notFound: "notFound"
        case .payloadTooLarge: "payloadTooLarge"
        case .unprocessable: "unprocessable"
        case .rateLimited: "rateLimited"
        case .serverError: "serverError"
        case .serviceUnavailable: "serviceUnavailable"
        case .unexpectedStatus(let code): "unexpectedStatus(\(code))"
        case .timedOut: "timedOut"
        case .cannotConnect: "cannotConnect"
        case .cancelled: "cancelled"
        case .audioUnreadable: "audioUnreadable"
        case .transport(let detail): "transport(\(detail))"
        }
    }
}

extension HealthStatus {
    var label: String {
        switch self {
        case .ready: "ready"
        case .notReady(let message): "notReady(\(message ?? "-"))"
        case .unauthorized(let message): "unauthorized(\(message ?? "-"))"
        case .unexpected(let status, let message): "unexpected(\(status), \(message ?? "-"))"
        case .unreachable(let kind): "unreachable(\(kind.label))"
        }
    }

    /// What the panel's banner says when the host will not take a dictation.
    var bannerMessage: String? {
        switch self {
        case .ready: nil
        case .notReady: "The host is still loading its model — the recording will be stored."
        case .unauthorized: "The host rejected the token — the recording will be stored."
        case .unexpected(let status, _): "The host answered with HTTP \(status) — the recording will be stored."
        case .unreachable: "The host cannot be reached — the recording will be stored."
        }
    }
}
