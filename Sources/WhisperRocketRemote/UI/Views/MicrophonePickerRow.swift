import SwiftUI

/// Which microphone to record from.
///
/// "System default" is a real choice, not the absence of one: it has to keep
/// following the default when AirPods connect, so it is stored as `nil` rather
/// than as the current default's UID.
struct MicrophonePickerRow: View {
    @Binding var selection: String?
    var devices: [AudioInputDevice]
    /// True when a UID was saved but that device is not plugged in right now.
    var isSavedDeviceMissing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker(L.settingsMicrophone, selection: $selection) {
                Text(L.settingsMicrophoneSystemDefault).tag(String?.none)
                ForEach(devices) { device in
                    Text(device.name).tag(String?.some(device.uid))
                }
                // A saved device that is unplugged has no row of its own, and a
                // picker with no matching tag renders blank — which looks like
                // a bug and hides the fact that the choice is still remembered.
                if isSavedDeviceMissing, let selection {
                    Text(selection).tag(String?.some(selection))
                }
            }

            if isSavedDeviceMissing {
                Label(L.settingsMicrophoneMissing, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
