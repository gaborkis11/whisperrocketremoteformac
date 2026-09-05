import Foundation

/// What the capsule is showing, as one flat value.
///
/// Deliberately payload-free: the details (`hostReachable`, `countdown`,
/// `attempt`, the level, the outcome) are separate properties on
/// ``PanelModelProviding``. A phase with associated values would make every one
/// of those a reason to rebuild the phase, and the capsule animates *on the
/// phase* — a countdown tick must not read as a phase change.
nonisolated enum DictationPhase: String, Equatable, Sendable, CaseIterable {
    case idle
    case recording
    case sending
    case done
    case failed

    /// How the menu-bar rocket is painted in this phase — the Linux tray's
    /// language: red records, amber sends, green means it landed.
    ///
    /// `.done` is the odd one: it is a flash, not a state, so ``MenuBarUI``
    /// drops back to `.idle` after ``StatusItemIcon/doneFlash``. `.failed` stays
    /// monochrome on purpose — the red badge is what says a recording is stuck,
    /// and a red rocket under a red dot would say it twice.
    var statusItemStyle: StatusItemIcon.Style {
        switch self {
        case .idle, .failed: .idle
        case .recording: .recording
        case .sending: .sending
        case .done: .done
        }
    }
}
