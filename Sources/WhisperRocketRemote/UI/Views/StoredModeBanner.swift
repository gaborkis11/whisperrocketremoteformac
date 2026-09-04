import SwiftUI

/// "The host is not answering — keep talking anyway."
///
/// This is the whole reason the health probe runs alongside the capture instead
/// of gating it: the user finds out the host is down *while the first sentence
/// is still being recorded*, not five minutes later when the upload fails. So
/// it has to be loud — a tinted, bordered row, not a grey footnote — and it has
/// to say the reassuring half out loud, because the instinct on seeing a
/// warning mid-sentence is to stop talking.
struct StoredModeBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Not colour alone: the icon carries the same message for anyone
            // who has Differentiate Without Color on.
            Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundStyle(.orange)
                .imageScale(.medium)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(L.storedModeTitle)
                    .font(.callout)
                    .bold()
                Text(L.storedModeDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.orange.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
