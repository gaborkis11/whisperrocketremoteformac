import SwiftUI

/// The capsule's measurements and its palette.
///
/// Unlike ``PanelMetrics``, this one names its own colours. The capsule is
/// **always dark** — it is a HUD that hangs over whatever the user is looking
/// at, and a light-mode capsule would be a white slab in the middle of a dark
/// editor — so the semantic styles that serve the panel so well have nothing to
/// resolve against here.
///
/// **Every size on this page comes out of ``scale``.** The approved design was
/// drawn at 560×88; that is `scale = 1`. Shipping it at full size turned out to
/// be far too much furniture for something that hangs under the menu bar while
/// you talk, so the pill is a fraction of the drawing and one line changes it.
///
/// Two things refuse to shrink with everything else, and they are what stops
/// the scale going lower:
///
/// * **Text never goes below 11 pt.** Below that a glanceable HUD stops being
///   glanceable, so the type has its own gentler curve (``typeScale``) and a
///   hard floor.
/// * **The stop button never goes below 28 pt.** It is the one thing in the
///   capsule a person has to hit, mid-sentence, without looking.
///
/// Because those two floors do not scale, the pill's *proportions* change a
/// little as it gets smaller: the words and the button keep their size while
/// the equalizer lane gives up the room. That is the intended trade — the lane
/// is scenery, the other two are the interface.
nonisolated enum CapsuleMetrics {
    // MARK: - The one number

    /// The shipped size, as a fraction of the approved 560×88 drawing.
    ///
    /// **This is the line to change.** Everything below is derived from it, so
    /// a different capsule is a different literal here and nothing else.
    static let defaultScale: Double = 0.45

    /// The scale in force.
    ///
    /// `WR_CAPSULE_SCALE` overrides it, which is how `--capsule-probe`
    /// photographs several candidate sizes in one run: the sizes are baked into
    /// `static let`s, so a second size means a second process. The override is
    /// clamped to a sane band and is not something the app ever sets for
    /// itself.
    static let scale: Double = scaleOverride ?? defaultScale

    static let scaleOverride: Double? = {
        guard let raw = ProcessInfo.processInfo.environment[scaleOverrideKey],
              let value = Double(raw),
              (0.25...1.0).contains(value)
        else { return nil }
        return value
    }()

    static let scaleOverrideKey = "WR_CAPSULE_SCALE"

    /// The scale as a whole percent — for probe filenames and log lines.
    static var scalePercent: Int { Int((scale * 100).rounded()) }

    /// Type shrinks at half the rate the box does. A HUD that is half the size
    /// is looked at from the same distance as one that is not.
    private static var typeScale: Double { 0.5 + 0.5 * scale }

    /// `base` at 100 %, rounded to a whole point and never below `floor`.
    /// Whole points because a 1.7-point bar on a 2× display is a blurred bar.
    private static func sized(_ base: Double, atLeast floor: Double = 0) -> Double {
        max(floor, (base * scale).rounded())
    }

    private static func fontSized(_ base: Double) -> Double {
        max(minimumFontSize, (base * typeScale).rounded())
    }

    /// The floor that decides how small the capsule can go.
    static let minimumFontSize: Double = 11
    /// The other floor: the stop target, mid-sentence, without looking.
    static let minimumButtonSize: Double = 28

    // MARK: - The pill

    static var width: Double { sized(560, atLeast: 200) }
    /// Tall enough for the button plus a margin, whatever the scale says.
    static var height: Double {
        max(sized(88), buttonSize + 2 * buttonMargin)
    }
    /// Exactly half the height, which is what makes it a capsule rather than a
    /// rounded rectangle.
    static var cornerRadius: Double { height / 2 }

    private static var buttonMargin: Double { 6 }

    static var leadingPadding: Double { sized(16, atLeast: 7) }
    static var trailingPadding: Double { sized(18, atLeast: 8) }
    static var itemSpacing: Double { sized(14, atLeast: 6) }

    /// The text column is a fixed width so the equalizer lane beside it does not
    /// jump every time the counter ticks from 0:09 to 0:10.
    ///
    /// Its floor is the reason the capsule's wording is its own (see ``L``):
    /// about a hundred points at 11 pt is eighteen characters, and every line
    /// the capsule shows has been written to fit in that rather than allowed to
    /// truncate.
    static var textColumnWidth: Double { sized(176, atLeast: 104) }

    /// What is left for the equalizer once the fixed parts have taken theirs.
    /// Not used for layout — the lane is `maxWidth: .infinity` and takes the
    /// slack itself — but the probe reports it, and it is the number that says
    /// whether a candidate size still has a picture in it.
    static var laneWidth: Double {
        width - leadingPadding - discSize - itemSpacing - textColumnWidth
            - itemSpacing - buttonSize - trailingPadding - itemSpacing
    }

    // MARK: - The parts

    static var discSize: Double { sized(54, atLeast: 24) }
    static var rocketSize: Double { (discSize * 26 / 54).rounded() }
    static var rocketStroke: Double { max(1, (rocketSize / 15.3 * 10).rounded() / 10) }
    /// The microphone glyph is an SF Symbol, whose drawn height runs a good deal
    /// taller than its point size — so it is asked for smaller than the rocket
    /// to end up the same size on screen.
    static var micSize: Double { (rocketSize * 0.82).rounded() }

    static var buttonSize: Double { sized(52, atLeast: minimumButtonSize) }
    static var stopSquare: Double { max(7, (buttonSize * 16 / 52).rounded()) }
    static var stopSquareRadius: Double { stopSquare / 4 }
    static var stopShadowRadius: Double { buttonSize * 0.17 }
    /// The tick, the cross and the retry arrow.
    static var glyphSize: Double { (buttonSize * 0.4).rounded() }
    static var spinnerSize: Double { (buttonSize * 0.5).rounded() }
    static var spinnerStroke: Double { max(2, (buttonSize * 0.058).rounded()) }

    static var laneHeight: Double { (height * 0.64).rounded() }

    // MARK: - The equalizer

    static var barWidth: Double { sized(3, atLeast: 2) }
    static var barSpacing: Double { sized(3, atLeast: 2) }
    static var barCornerRadius: Double { barWidth / 2 }
    /// Half-height, because the bars are drawn symmetrically about the midline.
    static var barMaxHalfHeight: Double { (laneHeight / 2 * 0.94).rounded() }
    /// A silent lane is a row of dots on the midline, not an empty box.
    static var barMinHalfHeight: Double { barWidth / 2 }

    /// Speech normalises to roughly 0.6 against the meter's dB floor; without a
    /// little gain the equalizer never reaches the top of its lane even when
    /// someone is talking straight into the microphone.
    static let equalizerGain: Double = 1.35
    /// The Gaussian's width, as a fraction of the bar count — the recipe the
    /// Linux app has always drawn with (`popup_window._draw_waveform`).
    static let equalizerSigmaRatio: Double = 0.25
    /// How much of a bar's height is *not* subject to the Gaussian.
    ///
    /// The recipe's bell, taken neat, closes to nothing two bars from each end,
    /// and on a lane this short that reads as a row of dots with a lens in the
    /// middle rather than as an equalizer. Keeping a third of the height out of
    /// the bell leaves the shape — middle tallest, ends quietest — while the
    /// ends still move.
    static let equalizerWeightFloor: Double = 0.35
    /// The bar-to-bar wobble, from the same recipe: enough to make the lane
    /// dance, not enough to make it noise.
    static let equalizerJitter: ClosedRange<Double> = 0.9...1.1

    // MARK: - Type

    static var titleFontSize: Double { fontSized(15) }
    static var secondaryTitleFontSize: Double { fontSized(14) }
    static var counterFontSize: Double { fontSized(13) }
    static var noteFontSize: Double { fontSized(12) }
    static var textLineSpacing: Double { max(1, sized(3)) }

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

    /// The equalizer after the microphone has closed: still there, no longer live.
    static var ghost: Color { amber.opacity(0.28) }
    static var ghostFailed: Color { danger.opacity(0.30) }

    // MARK: - Timings

    /// The same acknowledgement dwell the panel uses.
    static let doneDismissDelay: Duration = .milliseconds(1500)
    /// How long the acknowledgement takes to fade once its time is up.
    static let doneFade: Double = 0.35
    /// Escape's fade. Deliberately quick: the user asked for this to go away.
    static let cancelFade: Double = 0.8
    static let stageChange: Animation = .smooth(duration: 0.28)
    /// The equalizer's sampling cadence. Fixed, and not the buffer cadence: how
    /// often the microphone hands over a buffer is the hardware's choice, and a
    /// lane whose bar spacing depends on the audio interface looks broken.
    static let waveformSampleInterval: Duration = .milliseconds(50)

    /// One line for the probes and the logs: the numbers a size decision is
    /// actually made on.
    static var summary: String {
        "scale \(scalePercent)% — pill \(Int(width))×\(Int(height)), radius \(Int(cornerRadius)), "
            + "disc \(Int(discSize)), button \(Int(buttonSize)), "
            + "text column \(Int(textColumnWidth)), lane ≈\(Int(laneWidth))×\(Int(laneHeight)), "
            + "bars \(Int(barWidth))+\(Int(barSpacing)) pt, "
            + "type \(Int(titleFontSize))/\(Int(counterFontSize))/\(Int(noteFontSize)) pt"
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
