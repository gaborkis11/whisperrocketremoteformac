import SwiftUI

/// The login-item switch, plus the one thing that can make it impossible.
///
/// `SMAppService` only registers an app that lives in `/Applications`, so
/// running the build straight out of `dist/` leaves the switch dead. Saying so
/// is much better than a toggle that silently snaps back.
struct LaunchAtLoginRow: View {
    @Binding var isOn: Bool
    var isAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(L.settingsLaunchAtLogin, isOn: $isOn)
                .disabled(!isAvailable)

            if !isAvailable {
                Text(L.settingsLaunchAtLoginUnavailable)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
