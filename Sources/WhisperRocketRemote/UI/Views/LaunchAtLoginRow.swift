import SwiftUI

/// The login-item switch, plus the two things that can make it read “off” when
/// the user just asked for “on”.
///
/// `SMAppService` only registers an app that lives in `/Applications`, so
/// running the build straight out of `dist/` leaves the switch dead. And even
/// from `/Applications` macOS may park the registration in `requiresApproval`
/// until the user confirms it in Login Items. Saying either out loud is much
/// better than a toggle that silently snaps back.
struct LaunchAtLoginRow: View {
    @Binding var isOn: Bool
    var isAvailable: Bool
    var needsApproval: Bool
    var onOpenLoginItems: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(L.settingsLaunchAtLogin, isOn: $isOn)
                .disabled(!isAvailable)

            if !isAvailable {
                hint(L.settingsLaunchAtLoginUnavailable)
            } else if needsApproval {
                hint(L.settingsLaunchAtLoginNeedsApproval)
                Button(L.settingsLaunchAtLoginOpenSettings, action: onOpenLoginItems)
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
