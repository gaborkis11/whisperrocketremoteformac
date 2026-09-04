import SwiftUI
import WRCore

/// The capsule's middle lane while the microphone is open, and the ghost of it
/// afterwards.
///
/// A `Canvas`, for the same reason the cruise scene is one: thirty bars, a write
/// head and a row of dots is thirty-odd views to diff twenty times a second
/// against one immediate-mode draw that diffs nothing.
///
/// The write head does not move. It sits at a fixed point in the lane with the
/// past scrolling into it from the left and the room left to speak dotted out to
/// the right, which is the picture the approved design draws — and, unlike a
/// head that advances, it says the same thing at second three and at second two
/// hundred.
struct CapsuleWaveformView: View {
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

        var showsPlayhead: Bool { self == .live }
    }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            draw(&context, size: size)
        }
        .frame(maxWidth: .infinity)
        .frame(height: CapsuleMetrics.laneHeight)
        .modifier(WaveformAccessibility(level: mode == .live ? history.newest : nil))
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let midY = size.height / 2
        // Only the live lane keeps room ahead of the head; a ghost has nothing
        // left to say, so it fills the width instead of trailing off.
        let playheadX = mode.showsPlayhead
            ? (size.width * CapsuleMetrics.playheadPosition).rounded()
            : size.width

        drawBars(&context, midY: midY, playheadX: playheadX)
        guard mode.showsPlayhead else { return }
        drawPlayhead(&context, midY: midY, x: playheadX)
        drawRoomAhead(&context, midY: midY, from: playheadX, to: size.width)
    }

    /// Newest bar nearest the head, oldest at the left edge.
    private func drawBars(_ context: inout GraphicsContext, midY: Double, playheadX: Double) {
        let pitch = CapsuleMetrics.barWidth + CapsuleMetrics.barSpacing
        let count = min(Int(playheadX / pitch), history.capacity)
        let color = mode.barColor

        for age in 0..<count {
            let value = history.sample(agedBy: age)
            let height = CapsuleMetrics.barMinHeight
                + value * (CapsuleMetrics.barMaxHeight - CapsuleMetrics.barMinHeight)
            let x = playheadX - Double(age + 1) * pitch
            let rect = CGRect(
                x: x,
                y: midY - height / 2,
                width: CapsuleMetrics.barWidth,
                height: height
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: CapsuleMetrics.barCornerRadius),
                with: .color(color)
            )
        }
    }

    private func drawPlayhead(_ context: inout GraphicsContext, midY: Double, x: Double) {
        let line = CGRect(
            x: x - CapsuleMetrics.playheadLineWidth / 2,
            y: midY - CapsuleMetrics.playheadHeight / 2,
            width: CapsuleMetrics.playheadLineWidth,
            height: CapsuleMetrics.playheadHeight
        )
        context.fill(
            Path(roundedRect: line, cornerRadius: CapsuleMetrics.playheadLineWidth / 2),
            with: .color(CapsuleMetrics.amber)
        )

        let dot = CGRect(
            x: x - CapsuleMetrics.playheadDotSize / 2,
            y: line.minY - CapsuleMetrics.playheadDotSize / 2,
            width: CapsuleMetrics.playheadDotSize,
            height: CapsuleMetrics.playheadDotSize
        )
        context.fill(Path(ellipseIn: dot), with: .color(CapsuleMetrics.amber))
    }

    private func drawRoomAhead(
        _ context: inout GraphicsContext,
        midY: Double,
        from playheadX: Double,
        to maxX: Double
    ) {
        var x = playheadX + CapsuleMetrics.aheadDotSpacing
        while x <= maxX - CapsuleMetrics.aheadDotSize {
            let rect = CGRect(
                x: x - CapsuleMetrics.aheadDotSize / 2,
                y: midY - CapsuleMetrics.aheadDotSize / 2,
                width: CapsuleMetrics.aheadDotSize,
                height: CapsuleMetrics.aheadDotSize
            )
            context.fill(Path(ellipseIn: rect), with: .color(CapsuleMetrics.aheadDot))
            x += CapsuleMetrics.aheadDotSpacing
        }
    }
}

/// A meter that reads a percentage is far more useful to VoiceOver than a
/// picture of one; a ghost of a meter is not worth announcing at all.
private struct WaveformAccessibility: ViewModifier {
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
