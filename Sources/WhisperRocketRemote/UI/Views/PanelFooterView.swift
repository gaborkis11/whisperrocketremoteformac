import SwiftUI

/// Settings and Quit — the two things a menu-bar app has to offer somewhere,
/// and there is no menu to put them in.
struct PanelFooterView: View {
    var onSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        HStack {
            Button(L.actionSettings, action: onSettings)
            Spacer()
            Button(L.actionQuit, action: onQuit)
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
