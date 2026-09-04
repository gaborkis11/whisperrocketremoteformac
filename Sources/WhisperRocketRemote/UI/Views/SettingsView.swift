import KeyboardShortcuts
import SwiftUI

/// The settings window's content.
///
/// A plain grouped `Form`: this is a five-field settings sheet for one person's
/// machine, and the most stylish thing it can do is look exactly like every
/// other macOS settings window.
///
/// The shortcut name is injected rather than referenced directly so this view
/// has no opinion about which `KeyboardShortcuts.Name` the app registers — and
/// so `UIProbes` can open the real window against a throwaway name without
/// touching the user's stored hotkey.
struct SettingsView<Model: SettingsModelProviding>: View {
    @Bindable var model: Model
    var shortcutName: KeyboardShortcuts.Name

    var body: some View {
        Form {
            Section(L.settingsSectionGeneral) {
                LaunchAtLoginRow(
                    isOn: $model.launchAtLogin,
                    isAvailable: model.isLaunchAtLoginAvailable,
                    needsApproval: model.loginItemNeedsApproval,
                    onOpenLoginItems: model.openLoginItemsSettings
                )

                KeyboardShortcuts.Recorder(L.settingsHotkey, name: shortcutName)
                    .shortcutValidation(HotkeyShortcutValidator.validate)
            }

            Section(L.settingsSectionDictation) {
                MicrophonePickerRow(
                    selection: $model.inputDeviceUID,
                    devices: model.inputDevices,
                    isSavedDeviceMissing: model.isSavedInputDeviceMissing
                )

                Toggle(L.settingsSounds, isOn: $model.soundsEnabled)

                AutoPasteRow(
                    isOn: $model.autoPasteEnabled,
                    isAccessibilityGranted: model.isAccessibilityGranted,
                    onRequestPermission: model.requestAccessibilityPermission
                )
            }

            Section(L.settingsSectionHost) {
                TextField(L.settingsHostAddress, text: $model.host)
                // Grouping separators in a port number would be nonsense
                // ("8 771"), and the field is a number, not a string.
                TextField(L.settingsHostPort, value: $model.port, format: .number.grouping(.never))
                TokenFieldRow(hasToken: model.hasToken, setToken: model.setToken)

                if let message = model.hostValidationMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                } else {
                    Text(L.settingsHostTokenHint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            // All three can change while the window is closed — a microphone
            // gets unplugged, a permission is revoked in System Settings, the
            // login item is switched off there — so they are re-read rather
            // than cached at launch. `.task` only covers the *first* appearance
            // of this view, though: the window is reused, so the reopen case is
            // handled by `SettingsWindowController.onShow`.
            model.refreshInputDevices()
            model.refreshAccessibilityStatus()
            model.refreshLoginItemState()
        }
    }
}
