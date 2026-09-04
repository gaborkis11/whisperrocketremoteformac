import AppKit
import KeyboardShortcuts
import Observation
import SwiftUI
import WRCore
import WRNetwork

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The one owner of the dictation flow. The status item and the panel only
    /// read it.
    private(set) var controller: DictationController?

    private let hotkeys = HotkeyManager()
    /// The status item, the panel and the settings window, behind one object.
    /// Holds the panel and settings adapters alive with it.
    private var ui: MenuBarUI?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // The flow probe drives the real controller and terminates the process
        // when it is done, so nothing else may be wired up alongside it.
        if let request = FlowProbe.request(from: CommandLine.arguments) {
            FlowProbe.start(request)
            return
        }

        // F4's UI probes: the real status item, panel and settings window
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
            // `--show-panel`: opens the panel against this real controller a
            // beat after launch, so the integrated path can be checked without
            // a human clicking the menu bar. No-op without the flag.
            UIProbes.openPanelIfRequested(ui)
            NSLog("[wrr] controller ready: hotkey=%@ recordings=%d host=%@",
                  hotkeys.shortcut?.description ?? "<unset>",
                  controller.recordings.count,
                  controller.settings.host.isEmpty ? "<unset>" : controller.settings.host)
        } catch {
            NSLog("[wrr] controller could not be created: %@", String(describing: error))
        }
    }

}
