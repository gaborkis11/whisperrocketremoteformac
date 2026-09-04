import SwiftUI

/// The capsule's left-hand disc: the app saying what it is doing.
///
/// It is the rocket — the same ``RocketShape`` the menu-bar icon is drawn from,
/// stroked rather than filled, so the mark in the capsule and the mark in the
/// menu bar can never drift apart — **except while the microphone is open**,
/// where it is a microphone instead.
///
/// That one substitution is worth the inconsistency: recording is the only
/// stage where the disc has something to say that the rest of the capsule does
/// not already say louder, and a microphone says "you are being listened to"
/// from the corner of the eye, which is exactly where this thing is looked at.
/// The glyph is SF Symbols' outline `mic` at a weight chosen to sit next to the
/// rocket's stroke rather than beside it.
struct CapsuleRocketBadge: View {
    /// `true` only while recording.
    var isListening = false

    var body: some View {
        Circle()
            .fill(CapsuleMetrics.disc)
            .overlay {
                Circle().strokeBorder(CapsuleMetrics.discBorder, lineWidth: 1)
            }
            .overlay {
                mark
            }
            .frame(width: CapsuleMetrics.discSize, height: CapsuleMetrics.discSize)
            // The stage name and the elapsed time are read out beside it; a
            // second voice for the picture of them is noise.
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mark: some View {
        if isListening {
            Image(systemName: "mic")
                .font(.system(size: CapsuleMetrics.micSize, weight: .regular))
                .foregroundStyle(CapsuleMetrics.ink)
        } else {
            RocketShape()
                .stroke(
                    CapsuleMetrics.ink,
                    style: StrokeStyle(
                        lineWidth: CapsuleMetrics.rocketStroke,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: CapsuleMetrics.rocketSize, height: CapsuleMetrics.rocketSize)
        }
    }
}
