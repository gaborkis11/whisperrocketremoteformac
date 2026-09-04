import SwiftUI

/// What went wrong, in words, plus the host's own message underneath.
///
/// This stage does **not** auto-close — the panel stays up until the user
/// dismisses it — and it always ends on the same reassurance: the audio is
/// still on disk. Losing five minutes of speech is the failure this whole app
/// exists to prevent, so the panel says so out loud every time.
struct FailedStageView: View {
    var problem: DictationProblem

    var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
            Label {
                Text(problem.title)
                    .font(.headline)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Text(problem.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let hostMessage = problem.hostMessage {
                HostMessageView(message: hostMessage)
            }

            // Secondary, not tertiary: this is the sentence that stops the user
            // from thinking their five minutes are gone.
            Text(L.failureKept)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
