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

    /// The band the cruise animation gets: the starfield fills it and the
    /// rocket sits in the middle of it.
    static let cruiseSceneHeight: Double = 62
    /// The most the rocket motif is ever blown up. `1` is the Linux popup's own
    /// drawing at 1:1 (`_draw_rocket`'s units), which is 50 pt nose to tail —
    /// about a sixth of the panel's width, and as large as it can be before the
    /// flame runs out of room on the left.
    static let cruiseRocketScale: Double = 1
    /// The frame Reduce Motion holds. Not zero: frame zero is the flame at its
    /// shortest, and a still of that reads as an engine that has cut out.
    static let cruiseStillInstant: Double = 0.05

    static let barCount = 9
    static let barWidth: Double = 4
    static let barSpacing: Double = 4
    static let barMinHeight: Double = 4
    static let barMaxHeight: Double = 46

    /// How long the acknowledgement stays up before the panel closes itself.
    /// Long enough to read three words, short enough not to be in the way.
    static let doneDismissDelay: Duration = .milliseconds(1500)

    static let phaseChange: Animation = .smooth(duration: 0.28)
    static let levelChange: Animation = .snappy(duration: 0.18)
    /// One joke fading into the next. Slower than a phase change: this one is
    /// meant to be barely noticed.
    static let jokeChange: Animation = .easeInOut(duration: 0.35)
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
