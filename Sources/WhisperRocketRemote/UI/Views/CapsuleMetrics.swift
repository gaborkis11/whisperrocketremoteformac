import SwiftUI

/// The capsule's measurements and its palette.
///
/// Unlike ``PanelMetrics``, this one names its own colours. The capsule is
/// **always dark** — it is a HUD that hangs over whatever the user is looking
/// at, and a light-mode capsule would be a white slab in the middle of a dark
/// editor — so the semantic styles that serve the panel so well have nothing to
/// resolve against here. The values are the approved design's, verbatim.
nonisolated enum CapsuleMetrics {
    // MARK: - The pill

    static let width: Double = 560
    static let height: Double = 88
    /// Exactly half the height, which is what makes it a capsule rather than a
    /// rounded rectangle.
    static let cornerRadius: Double = 44

    static let leadingPadding: Double = 16
    static let trailingPadding: Double = 18
    static let itemSpacing: Double = 14

    /// The text column is a fixed width so the waveform lane beside it does not
    /// jump every time the counter ticks from 0:09 to 0:10.
    static let textColumnWidth: Double = 176

    // MARK: - The parts

    static let discSize: Double = 54
    static let rocketSize: Double = 26
    static let rocketStroke: Double = 1.7
    static let buttonSize: Double = 52
    static let stopSquare: Double = 16
    static let stopSquareRadius: Double = 4
    static let laneHeight: Double = 56

    static let barWidth: Double = 3
    static let barSpacing: Double = 3
    static let barCornerRadius: Double = 2
    static let barMaxHeight: Double = 40
    static let barMinHeight: Double = 3
    /// Where the write head sits in the lane. Left of it is what has been said,
    /// right of it is the room left to say it in.
    static let playheadPosition: Double = 0.72
    static let playheadDotSize: Double = 7
    static let playheadLineWidth: Double = 2
    static let playheadHeight: Double = 45
    static let aheadDotSize: Double = 3
    static let aheadDotSpacing: Double = 12

    // MARK: - Colours

    static let background = rgb(0x16_16_19)
    static let border = Color.white.opacity(0.07)
    /// The one-pixel lip along the top edge that keeps the pill from reading as
    /// a flat hole in the screen.
    static let topHighlight = Color.white.opacity(0.06)
    static let disc = rgb(0x0C_0C_0E)
    static let discBorder = Color.white.opacity(0.10)

    static let ink = rgb(0xF4_F4_F5)
    static let amber = rgb(0xF5_B8_2E)
    static let subdued = rgb(0x9A_9A_A2)

    static let stopTop = rgb(0xEF_5A_5F)
    static let stopBottom = rgb(0xD9_3A_40)
    static let stopShadow = rgb(0xD9_3A_40).opacity(0.35)
    static var stopGradient: LinearGradient {
        LinearGradient(colors: [stopTop, stopBottom], startPoint: .top, endPoint: .bottom)
    }

    static let danger = rgb(0xE5_48_4D)
    /// A failure changes the pill's own edge — the one thing on screen that is
    /// visible from the corner of the eye.
    static var failedBorder: Color { danger.opacity(0.35) }

    /// The waveform after the microphone has closed: still there, no longer live.
    static var ghost: Color { amber.opacity(0.18) }
    static var ghostFailed: Color { danger.opacity(0.25) }
    static var aheadDot: Color { amber.opacity(0.30) }

    // MARK: - Timings

    /// The same acknowledgement dwell the panel uses.
    static let doneDismissDelay: Duration = .milliseconds(1500)
    /// How long the acknowledgement takes to fade once its time is up.
    static let doneFade: Double = 0.35
    /// Escape's fade. Deliberately quick: the user asked for this to go away.
    static let cancelFade: Double = 0.8
    static let stageChange: Animation = .smooth(duration: 0.28)
    /// The waveform's sampling cadence. Fixed, and not the buffer cadence: how
    /// often the microphone hands over a buffer is the hardware's choice, and a
    /// waveform whose spacing depends on the audio interface looks broken.
    static let waveformSampleInterval: Duration = .milliseconds(50)

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
