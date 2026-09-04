import SwiftUI

/// The panel's shared measurements and timings.
///
/// One place, so the panel reads as a single object rather than a pile of
/// views that each guessed at their own padding. Colours are deliberately
/// absent: everything visible uses semantic styles (`.primary`, `.secondary`,
/// `.tint`) so vibrancy and the light/dark switch keep working for free.
nonisolated enum PanelMetrics {
    /// Fixed width. The height follows the content — see `PanelController`.
    static let width: Double = 300

    /// Minimum height of the stage area, so a phase change does not make the
    /// whole panel jump.
    static let stageHeight: Double = 104

    static let cornerRadius: Double = 14
    static let padding: Double = 14
    static let rowSpacing: Double = 6
    static let sectionSpacing: Double = 10

    /// The rocket mark in the header.
    static let markSize: Double = 15
    /// The rocket in the launch animation.
    static let launchRocketWidth: Double = 26

    static let barCount = 9
    static let barWidth: Double = 4
    static let barSpacing: Double = 4
    static let barMinHeight: Double = 4
    static let barMaxHeight: Double = 46

    /// How long the acknowledgement stays up before the panel closes itself.
    /// Long enough to read three words, short enough not to be in the way.
    static let doneDismissDelay: Duration = .milliseconds(1500)

    /// One rocket launch, start to fade-out. Sized to the measured host round
    /// trip so the loop rarely restarts mid-flight for a short dictation.
    static let launchDuration: Double = 3.4

    static let phaseChange: Animation = .smooth(duration: 0.28)
    static let levelChange: Animation = .snappy(duration: 0.18)
    /// Reduce Motion still needs *something*, or values teleport; a short
    /// cross-fade reads as a change without moving anything across the screen.
    static let reducedMotionChange: Animation = .easeInOut(duration: 0.18)

    static func phaseAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedMotionChange : phaseChange
    }

    static func levelAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.12) : levelChange
    }
}
