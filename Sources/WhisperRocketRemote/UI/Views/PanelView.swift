import SwiftUI

/// The panel's whole content.
///
/// Generic over the model rather than taking `any PanelModelProviding`, so the
/// compiler can see the concrete `@Observable` type and SwiftUI's observation
/// tracking has nothing to lose on the way through an existential.
///
/// No background of its own: the vibrancy comes from the `NSVisualEffectView`
/// this is hosted in, and painting over it would be painting over the point.
struct PanelView<Model: PanelModelProviding>: View {
    var model: Model
    /// Opening settings and quitting belong to the UI, not to the orchestrator,
    /// so they arrive as closures rather than as model methods.
    var onSettings: () -> Void
    var onQuit: () -> Void
    /// The panel's own laid-out size, reported back so the window can be
    /// resized around it. Asking AppKit for `fittingSize` after a model change
    /// races SwiftUI's update; letting SwiftUI say what it settled on does not.
    var onContentSize: (CGSize) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            PanelHeaderView(phase: model.phase, reduceMotion: reduceMotion)
                .padding(.horizontal, PanelMetrics.padding)
                .padding(.top, PanelMetrics.padding - 3)
                .padding(.bottom, 9)

            Divider()

            PanelStageView(model: model)
                .padding(.horizontal, PanelMetrics.padding)
                .padding(.vertical, PanelMetrics.padding)

            if !model.recordings.isEmpty {
                Divider()
                RecordingListView(
                    recordings: model.recordings,
                    attempt: model.attempt,
                    maxAttempts: model.maxAttempts,
                    onResend: model.resend
                )
                .padding(.horizontal, PanelMetrics.padding)
                .padding(.vertical, 8)
            }

            Divider()

            PanelFooterView(onSettings: onSettings, onQuit: onQuit)
                .padding(.horizontal, PanelMetrics.padding - 4)
                .padding(.vertical, 5)
        }
        .frame(width: PanelMetrics.width)
        .fixedSize(horizontal: false, vertical: true)
        // A background is sized to the view it decorates, so this proxy carries
        // the panel's *settled* size rather than whatever was proposed to it.
        .background {
            Color.clear
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                    onContentSize(size)
                }
        }
        // The rounding is masked by the hosting `NSVisualEffectView`; this only
        // adds the hairline that gives the panel an edge against a light
        // wallpaper, in whichever colour the current appearance calls for.
        .overlay {
            RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius)
                .strokeBorder(.separator, lineWidth: 1)
        }
        .animation(PanelMetrics.phaseAnimation(reduceMotion: reduceMotion), value: model.recordings)
    }
}
