import SwiftUI
import WRCore

/// The recording ring, newest first.
///
/// At most three rows ever — the ring holds three — so a plain `VStack` is
/// right here and a `List` would only add scroll chrome the panel does not
/// want.
struct RecordingListView: View {
    var recordings: [RecordingMeta]
    var attempt: Int
    var maxAttempts: Int
    var onResend: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L.recordingsTitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            ForEach(recordings) { recording in
                RecordingRowView(
                    recording: recording,
                    attemptText: attemptText(for: recording),
                    onResend: { onResend(recording.id) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Only the entry that is actually in flight gets a counter, and only once
    /// there is something to count: "1/3" on a first attempt is noise, and on a
    /// row that is merely waiting it would be a lie.
    private func attemptText(for recording: RecordingMeta) -> String? {
        guard recording.status == .sending, attempt > 1, maxAttempts > 1 else { return nil }
        return L.recordingAttempt(attempt, of: maxAttempts)
    }
}
