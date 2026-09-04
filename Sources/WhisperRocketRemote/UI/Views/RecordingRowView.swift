import SwiftUI
import WRCore

/// One entry of the three-slot ring.
struct RecordingRowView: View {
    var recording: RecordingMeta
    /// The live attempt counter, but only for the entry actually uploading.
    var attemptText: String?
    var onResend: () -> Void

    /// A `sent` recording has nothing left to do; the other three states can
    /// all be pushed at the host again.
    private var canResend: Bool {
        recording.status == .pending || recording.status == .failed
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(recording.createdAt, format: .relative(presentation: .named))
                    .font(.callout)
                Text(Duration.seconds(recording.durationSeconds), format: .time(pattern: .minuteSecond))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            RecordingStatusChip(status: recording.status, attempt: attemptText)

            // Icon-only *visually*; the text label is still there for VoiceOver
            // and Voice Control.
            Button(action: onResend) {
                Label(L.recordingResend, systemImage: "arrow.clockwise")
            }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .controlSize(.small)
                .disabled(!canResend)
                // Kept in the layout so the rows stay aligned, but out of the
                // accessibility tree entirely — VoiceOver should not announce a
                // button that cannot be pressed.
                .opacity(canResend ? 1 : 0)
                .accessibilityHidden(!canResend)
                .help(L.recordingResend)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }
}
