import SwiftUI

/// The capsule's right-hand disc: the one thing in it you can press.
///
/// It is a *button* in exactly two stages — stop and retry — and a state light
/// in the other three. That is deliberate: a control that sometimes does
/// nothing teaches people not to press it, so the spinner, the tick and the
/// cross are not buttons at all and do not take focus.
struct CapsuleActionButton: View {
    var stage: CapsuleStage
    var reduceMotion: Bool
    /// `false` hides the retry button: there is nothing this failure could
    /// usefully re-send.
    var canRetry: Bool
    var onStop: () -> Void
    var onRetry: () -> Void

    var body: some View {
        Group {
            switch stage {
            case .recording:
                Button(action: onStop) { stopFace }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.stopRecording)

            case .sending:
                spinnerFace

            case .done:
                doneFace

            case .failed:
                if canRetry {
                    Button(action: onRetry) { retryFace }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L.recordingResend)
                } else {
                    // The slot stays: a capsule that changes width when a
                    // button disappears would jump under the menu bar.
                    Color.clear
                }

            case .cancelled:
                cancelledFace
            }
        }
        .frame(width: CapsuleMetrics.buttonSize, height: CapsuleMetrics.buttonSize)
    }

    // MARK: - Faces

    private var stopFace: some View {
        Circle()
            .fill(CapsuleMetrics.stopGradient)
            .overlay {
                RoundedRectangle(cornerRadius: CapsuleMetrics.stopSquareRadius, style: .continuous)
                    .fill(.white)
                    .frame(width: CapsuleMetrics.stopSquare, height: CapsuleMetrics.stopSquare)
            }
            .shadow(color: CapsuleMetrics.stopShadow, radius: CapsuleMetrics.stopShadowRadius, y: 3)
            .frame(width: CapsuleMetrics.buttonSize, height: CapsuleMetrics.buttonSize)
    }

    private var spinnerFace: some View {
        Circle()
            .fill(CapsuleMetrics.disc)
            .overlay {
                if reduceMotion {
                    // Reduce Motion's promise is no movement, not no picture:
                    // the arc stays, the rotation goes, and the joke below the
                    // title carries the "still working" message instead.
                    spinnerArc(rotation: -90)
                } else {
                    TimelineView(.animation) { context in
                        spinnerArc(rotation: Self.angle(at: context.date))
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel(L.sendingTitle)
    }

    private func spinnerArc(rotation: Double) -> some View {
        Circle()
            .trim(from: 0, to: 0.3)
            .stroke(
                CapsuleMetrics.amber,
                style: StrokeStyle(lineWidth: CapsuleMetrics.spinnerStroke, lineCap: .round)
            )
            .rotationEffect(.degrees(rotation))
            .frame(width: CapsuleMetrics.spinnerSize, height: CapsuleMetrics.spinnerSize)
    }

    private var doneFace: some View {
        Circle()
            .fill(CapsuleMetrics.amber)
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: CapsuleMetrics.glyphSize, weight: .bold))
                    .foregroundStyle(CapsuleMetrics.background)
            }
            .accessibilityHidden(true)
    }

    private var retryFace: some View {
        Circle()
            .fill(CapsuleMetrics.stopGradient)
            .overlay {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: CapsuleMetrics.glyphSize, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: CapsuleMetrics.stopShadow, radius: CapsuleMetrics.stopShadowRadius, y: 3)
    }

    private var cancelledFace: some View {
        Circle()
            .fill(CapsuleMetrics.disc)
            .overlay {
                Circle().strokeBorder(CapsuleMetrics.discBorder, lineWidth: 1)
            }
            .overlay {
                Image(systemName: "xmark")
                    .font(.system(size: CapsuleMetrics.glyphSize * 0.9, weight: .bold))
                    .foregroundStyle(CapsuleMetrics.ink)
            }
            .accessibilityHidden(true)
    }

    /// One turn every 1.1 s, from the wall clock rather than from a repeating
    /// animation, so nothing has to be restarted when the view is rebuilt.
    private static func angle(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360 - 90
    }
}
