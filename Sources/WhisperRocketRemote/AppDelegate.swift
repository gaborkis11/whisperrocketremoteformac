import AppKit
import KeyboardShortcuts
import Observation
import SwiftUI
import WRCore
import WRNetwork

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The one owner of the dictation flow. The status item, its menu and the
    /// capsule only read it.
    private(set) var controller: DictationController?

    private let hotkeys = HotkeyManager()
    /// The status item, the capsule and the windows, behind one object. Holds
    /// the two model adapters alive with it.
    private var ui: MenuBarUI?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Before anything can read a preference: on a fresh install the sounds
        // switch has to start on and the port has to be 8771, and
        // `UserDefaults.bool`/`integer` would answer `false`/`0` for keys nobody
        // has written yet.
        Settings.registerDefaults()

        // The flow probe drives the real controller and terminates the process
        // when it is done, so nothing else may be wired up alongside it.
        if let request = FlowProbe.request(from: CommandLine.arguments) {
            FlowProbe.start(request)
            return
        }

        // F4's UI probes: the real status item, capsule and settings window
        // against the *mock* models. `--icon-probe`, `--l10n-probe` and
        // `--render-probe` print and exit; `--ui-probe` returns true and leaves
        // the UI running, so nothing real may be installed after it.
        if UIProbes.runIfRequested(arguments: CommandLine.arguments) {
            return
        }

        installController()

        SmokeReport.emit(shortcut: hotkeys.shortcut)
    }

    private func installController() {
        do {
            let controller = try DictationController()
            self.controller = controller
            hotkeys.start { [weak controller] in controller?.toggle() }
            let ui = MenuBarUI(
                panelModel: DictationPanelModel(controller: controller),
                settingsModel: DictationSettingsModel(controller: controller),
                shortcutName: .toggleDictation
            )
            self.ui = ui
            // `--show-settings`: opens the settings window against this real
            // controller, twice,
            // so the reopen path is actually exercised. No-op without the flag.
            UIProbes.openSettingsIfRequested(ui)
            NSLog("[wrr] controller ready: hotkey=%@ recordings=%d host=%@",
                  hotkeys.shortcut?.description ?? "<unset>",
                  controller.recordings.count,
                  controller.settings.host.isEmpty ? "<unset>" : controller.settings.host)
        } catch {
            NSLog("[wrr] controller could not be created: %@", String(describing: error))
        }
    }

}
