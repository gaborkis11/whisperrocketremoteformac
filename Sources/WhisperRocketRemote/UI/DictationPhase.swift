import Foundation

/// What the panel is showing, as one flat value.
///
/// Deliberately payload-free: the details (`hostReachable`, `countdown`,
/// `attempt`, the level, the outcome) are separate properties on
/// ``PanelModelProviding``. A phase with associated values would make every one
/// of those a reason to rebuild the phase, and the panel animates *on the
/// phase* — a countdown tick must not read as a phase change.
nonisolated enum DictationPhase: String, Equatable, Sendable, CaseIterable {
    case idle
    case recording
    case sending
    case done
    case failed

    /// The panel must not vanish under the user while this is true: a stray
    /// click elsewhere leaves it open, because it is showing something that is
    /// still happening.
    ///
    /// A *failure* is deliberately not in here. It must not close on a timer —
    /// that is what ``dismissesItself`` is for — but a click elsewhere is the
    /// user saying "read, move on", and refusing that would be rude.
    var holdsPanelOpen: Bool {
        self == .recording || self == .sending
    }

    /// Only the acknowledgement gets out of the way on its own.
    var dismissesItself: Bool {
        self == .done
    }

    /// Whether the menu-bar rocket is drawn filled rather than as an outline.
    var wantsFilledStatusIcon: Bool {
        self == .recording || self == .sending
    }

    var localizedTitle: String {
        switch self {
        case .idle: L.statusIdle
        case .recording: L.statusRecording
        case .sending: L.statusSending
        case .done: L.statusDone
        case .failed: L.statusFailed
        }
    }
}
