import SwiftUI

/// The capsule's left-hand disc: the app saying who is talking.
///
/// The same ``RocketShape`` the menu-bar icon is drawn from, stroked rather than
/// filled — one path, both looks — so the mark in the capsule and the mark in
/// the menu bar can never drift apart.
struct CapsuleRocketBadge: View {
    var body: some View {
        Circle()
            .fill(CapsuleMetrics.disc)
            .overlay {
                Circle().strokeBorder(CapsuleMetrics.discBorder, lineWidth: 1)
            }
            .overlay {
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
            .frame(width: CapsuleMetrics.discSize, height: CapsuleMetrics.discSize)
            .accessibilityHidden(true)
    }
}
