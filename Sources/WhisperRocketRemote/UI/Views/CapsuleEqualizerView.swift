import SwiftUI
import WRCore

/// The capsule's middle lane while the microphone is open, and the ghost of it
/// afterwards.
///
/// A classic equalizer, not a waveform: bars across the whole lane, each one
/// drawn symmetrically up **and** down from the midline, with no write head and
/// nothing trailing off to the right. That is the picture the Linux app has
/// always drawn (`popup_window._draw_waveform`) and the one that reads as
/// "listening" at a glance, at any size.
///
/// Three things shape a bar, in this order:
///
/// 1. **The level**, from ``WaveformHistory`` — newest bar at the right, older
///    ones sliding away to the left, so a loud syllable travels across the lane
///    instead of every bar moving as one block.
/// 2. **A Gaussian weight**, tallest in the middle and tailing off at both
///    ends. It is what turns a row of bars into a shape; without it the lane
///    reads as a bar chart.
/// 3. **A little wobble**, 0.9–1.1, so neighbouring bars never line up into a
///    smooth curve. It is seeded from the history's sample counter rather than
///    from a random generator or the clock: the same history always draws the
///    same picture — which is what makes a probe still reproducible — and the
///    wobble re-rolls with each new *sample*, twenty times a second, rather
///    than with each frame.
///
/// A `Canvas`, for the same reason the cruise scene is one: thirty-odd bars is
/// thirty-odd views to diff twenty times a second against one immediate-mode
/// draw that diffs nothing.
struct CapsuleEqualizerView: View {
    var history: WaveformHistory
    var mode: Mode

    /// Only the live lane says a level out loud; a ghost is scenery.
    enum Mode: Equatable {
        case live
        case ghost
        case ghostFailed

        var barColor: Color {
            switch self {
            case .live: CapsuleMetrics.amber
            case .ghost: CapsuleMetrics.ghost
            case .ghostFailed: CapsuleMetrics.ghostFailed
            }
        }

        /// A finished dictation's lane is a still photograph of the last thing
        /// said. Wobbling it would suggest a microphone that is still open.
        var wobbles: Bool { self == .live }
    }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            draw(&context, size: size)
        }
        .frame(maxWidth: .infinity)
        .frame(height: CapsuleMetrics.laneHeight)
        .modifier(EqualizerAccessibility(level: mode == .live ? history.newest : nil))
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        let pitch = CapsuleMetrics.barWidth + CapsuleMetrics.barSpacing
        let count = min(
            history.capacity,
            Int((size.width + CapsuleMetrics.barSpacing) / pitch)
        )
        guard count > 0 else { return }

        // Centred: the leftover half-gap is split between the two ends rather
        // than left dangling on the right.
        let span = Double(count) * pitch - CapsuleMetrics.barSpacing
        let startX = ((size.width - span) / 2).rounded()
        let midY = (size.height / 2).rounded()
        let color = mode.barColor

        for index in 0..<count {
            let half = halfHeight(at: index, of: count)
            let rect = CGRect(
                x: startX + Double(index) * pitch,
                y: midY - half,
                width: CapsuleMetrics.barWidth,
                height: half * 2
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: CapsuleMetrics.barCornerRadius),
                with: .color(color)
            )
        }
    }

    /// How far this bar reaches above the midline — and, mirrored, below it.
    private func halfHeight(at index: Int, of count: Int) -> Double {
        // Newest sample on the right, oldest on the left.
        let level = history.sample(agedBy: count - 1 - index)
        let amplitude = min(1, level * CapsuleMetrics.equalizerGain)
        let wobble = mode.wobbles ? Self.wobble(bar: index, tick: history.tick) : 1
        let reach = amplitude * Self.weight(at: index, of: count) * wobble
        return max(
            CapsuleMetrics.barMinHalfHeight,
            (reach * CapsuleMetrics.barMaxHalfHeight).rounded()
        )
    }

    /// The Gaussian envelope: tallest in the middle, quiet at both ends.
    static func weight(at index: Int, of count: Int) -> Double {
        guard count > 1 else { return 1 }
        let centre = Double(count - 1) / 2
        let sigma = max(1, Double(count) * CapsuleMetrics.equalizerSigmaRatio)
        let distance = Double(index) - centre
        let bell = exp(-(distance * distance) / (2 * sigma * sigma))
        let floor = CapsuleMetrics.equalizerWeightFloor
        return floor + (1 - floor) * bell
    }

    /// A deterministic stand-in for `random(0.9...1.1)`: SplitMix64's finaliser
    /// over the bar and the sample counter. Same inputs, same lane — so a still
    /// is reproducible and a redraw is never *caused* by the wobble.
    static func wobble(bar: Int, tick: Int) -> Double {
        var hash = UInt64(bitPattern: Int64(bar)) &* 0x9E37_79B9_7F4A_7C15
        hash ^= UInt64(bitPattern: Int64(tick)) &* 0xBF58_476D_1CE4_E5B9
        hash ^= hash >> 30
        hash &*= 0xBF58_476D_1CE4_E5B9
        hash ^= hash >> 27
        hash &*= 0x94D0_49BB_1331_11EB
        hash ^= hash >> 31

        let unit = Double(hash >> 11) * (1.0 / 9_007_199_254_740_992.0)
        let range = CapsuleMetrics.equalizerJitter
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

/// A meter that reads a percentage is far more useful to VoiceOver than a
/// picture of one; a ghost of a meter is not worth announcing at all.
private struct EqualizerAccessibility: ViewModifier {
    var level: Double?

    func body(content: Content) -> some View {
        if let level {
            content
                .accessibilityElement()
                .accessibilityLabel(L.statusRecording)
                .accessibilityValue(Text(level, format: .percent.precision(.fractionLength(0))))
        } else {
            content.accessibilityHidden(true)
        }
    }
}
