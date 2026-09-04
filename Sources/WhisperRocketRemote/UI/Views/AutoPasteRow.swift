import SwiftUI

/// The auto-typing switch and its permission.
///
/// Turning it on is what asks for Accessibility — that is the moment the
/// request makes sense, and asking at launch instead would be a prompt with no
/// context. If the permission is refused (or later revoked) the switch stays
/// on, the warning stays up, and dictation still works: the text always lands
/// on the clipboard regardless.
struct AutoPasteRow: View {
    @Binding var isOn: Bool
    var isAccessibilityGranted: Bool
    var onRequestPermission: () -> Void

    private var needsPermission: Bool { isOn && !isAccessibilityGranted }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(L.settingsAutoPaste, isOn: $isOn)

            Text(L.settingsAutoPasteHint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if needsPermission {
                HStack(spacing: 8) {
                    Label(L.settingsAutoPasteNeedsPermission, systemImage: "lock.trianglebadge.exclamationmark")
                        .foregroundStyle(.orange)
                        .font(.callout)
                    Button(L.settingsAutoPasteGrant, action: onRequestPermission)
                        .controlSize(.small)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: isOn) { _, newValue in
            guard newValue, !isAccessibilityGranted else { return }
            onRequestPermission()
        }
    }
}
