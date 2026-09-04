import SwiftUI
import WRCore

/// The status of one ring entry, as an icon plus a word.
///
/// Icon *and* word, never colour alone — with Differentiate Without Color on,
/// a green dot and an orange dot are the same dot.
struct RecordingStatusChip: View {
    var status: RecordingMeta.Status
    /// Shown only for the entry currently in flight: "2/3".
    var attempt: String?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbolName)
                .imageScale(.small)
            Text(title)
                .font(.caption)
            if let attempt {
                Text(attempt)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch status {
        case .pending: L.recordingStatusPending
        case .sending: L.recordingStatusSending
        case .sent: L.recordingStatusSent
        case .failed: L.recordingStatusFailed
        }
    }

    private var symbolName: String {
        switch status {
        case .pending: "clock"
        case .sending: "arrow.up.circle"
        case .sent: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var tint: AnyShapeStyle {
        switch status {
        case .pending: AnyShapeStyle(.secondary)
        case .sending: AnyShapeStyle(.tint)
        case .sent: AnyShapeStyle(.green)
        case .failed: AnyShapeStyle(.orange)
        }
    }
}
