import SwiftUI

/// The rocket and its exhaust as one object, so a single animator can move
/// both and they can never come apart.
struct RocketTrailView: View {
    /// 0…1 — how long the exhaust is right now.
    var trail: Double

    var body: some View {
        ZStack(alignment: .top) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.orange.opacity(0.9), .pink.opacity(0.35), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(
                    width: PanelMetrics.launchRocketWidth * 0.34,
                    height: 12 + trail * 30
                )
                .blur(radius: 2.5)
                .offset(y: PanelMetrics.launchRocketWidth * 0.82)
                .opacity(trail)

            RocketMarkView(style: .filled, size: PanelMetrics.launchRocketWidth)
        }
        .accessibilityHidden(true)
    }
}
