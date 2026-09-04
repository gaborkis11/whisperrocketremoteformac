import SwiftUI

/// The panel at rest: what the app is, how to start it, and nothing else.
struct IdleStageView: View {
    /// The hotkey as a readable string, or `nil` when none is set.
    var shortcutDescription: String?
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: PanelMetrics.sectionSpacing) {
            RocketMarkView(style: .outline, size: 38)
                .foregroundStyle(.tint)

            Text(shortcutDescription.map(L.idleHint(shortcut:)) ?? L.idleHintNoShortcut)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(L.startRecording, action: onStart)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
    }
}
