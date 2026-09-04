import SwiftUI

/// The host's own plain-text error body, quoted verbatim.
///
/// Kept because the host frequently knows more than its status code does, and
/// a sentence from it is worth more than any wording invented here. Quoted
/// (indented, monospaced, selectable) so it is clearly *the host talking*, and
/// so it can be copied into a bug report.
struct HostMessageView: View {
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L.failureHostSaid)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text(message)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.horizontal, 7)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
        }
    }
}
