import SwiftUI

/// The static rocket, used wherever the app has to sign its name: the panel
/// header, the acknowledgement, the launch animation's payload.
///
/// No `#Preview` anywhere in this project on purpose — there is no `.xcodeproj`
/// to open one in, and the `#Preview` macro drags `libPreviewsMacros.dylib`
/// into the build. `UIProbes` is the visual check instead, and it runs the real
/// panel rather than a preview of it.
struct RocketMarkView: View {
    enum Style: Equatable, Sendable {
        case outline
        case filled
    }

    var style: Style = .outline
    var size: Double = PanelMetrics.markSize

    var body: some View {
        // Both looks come from one shape, switched by opacity rather than by
        // branching: the view keeps its identity, so a style change animates.
        RocketShape()
            .fill(
                .foreground.opacity(style == .filled ? 1 : 0),
                style: FillStyle(eoFill: true)
            )
            .overlay {
                RocketShape()
                    .stroke(
                        .foreground.opacity(style == .outline ? 1 : 0),
                        style: StrokeStyle(lineWidth: max(1, size / 13), lineJoin: .round)
                    )
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
