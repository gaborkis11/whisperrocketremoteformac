import AppKit
import WRCore

/// The menu behind the menu-bar rocket.
///
/// A real `NSMenu`, not a drawn panel: it is four lines of text and two of them
/// open windows, which is precisely what the menu bar is for. What used to be a
/// 300-point column of SwiftUI is now the system's own widget — it tracks the
/// mouse, it takes the keyboard, it dismisses itself, and it costs nothing to
/// keep correct.
///
/// The contents are rebuilt in `menuNeedsUpdate(_:)` rather than observed. A
/// menu is only ever looked at in the instant after it is asked for, so
/// "rebuild it then" is both simpler than an observation and strictly more
/// accurate than one.
///
/// **Not generic, and must not become generic** — the same optimiser segfault
/// that shaped ``MenuBarUI`` (see the note there). The model arrives as an
/// existential; nothing here needs its concrete type, because a menu is strings
/// and closures rather than a SwiftUI tree.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()

    private let model: any PanelModelProviding
    /// Raised before the menu appears: the capsule gets out of the way, exactly
    /// as it did for the old panel's click.
    private let onWillOpen: () -> Void
    private let onSettings: () -> Void
    private let onAbout: () -> Void

    init(
        model: any PanelModelProviding,
        onWillOpen: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onAbout: @escaping () -> Void
    ) {
        self.model = model
        self.onWillOpen = onWillOpen
        self.onSettings = onSettings
        self.onAbout = onAbout
        super.init()
        menu.delegate = self
        // Every item says for itself whether it can be used. Automatic enabling
        // walks the responder chain for each action, and an accessory app with
        // no main menu has nothing useful in one.
        menu.autoenablesItems = false
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        onWillOpen()
    }

    // MARK: - Building

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        // `recordings` is newest first, so the ring's one entry is `first`.
        let last = model.recordings.first
        let info = NSMenuItem(title: Self.lastRecordTitle(last), action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)

        if let last {
            // Always enabled, whatever the status says: Gábor's rule is that the
            // last recording can be sent again as often as he likes — including
            // one that already arrived.
            let resend = NSMenuItem(
                title: L.recordingResend,
                action: #selector(sendAgain),
                keyEquivalent: ""
            )
            resend.target = self
            resend.representedObject = last.id
            menu.addItem(resend)
        }

        menu.addItem(.separator())
        menu.addItem(item(title: L.actionSettings, action: #selector(openSettings)))
        menu.addItem(item(title: L.menuAbout, action: #selector(openAbout)))
        menu.addItem(.separator())
        menu.addItem(item(title: L.actionQuit, action: #selector(quit)))
    }

    private func item(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// "Last record: 0:42 — Sent ✓", or the empty-ring line.
    ///
    /// Built as a string rather than as a `Text`: there is no SwiftUI in a menu,
    /// so the formatters are called directly.
    private static func lastRecordTitle(_ meta: RecordingMeta?) -> String {
        guard let meta else { return L.menuNoRecordings }
        let length = Duration.seconds(meta.durationSeconds.rounded())
            .formatted(.time(pattern: .minuteSecond))
        return L.menuLastRecord(length, statusTitle(meta.status))
    }

    /// The status word, plus a mark for the two statuses a person acts on. The
    /// mark is punctuation and stays out of the `.strings` files; the word is
    /// the localized one the recording list used to show.
    private static func statusTitle(_ status: RecordingMeta.Status) -> String {
        switch status {
        case .pending: L.recordingStatusPending
        case .sending: L.recordingStatusSending
        case .sent: L.recordingStatusSent + " ✓"
        case .failed: L.recordingStatusFailed + " ⚠"
        }
    }

    // MARK: - Actions

    @objc private func sendAgain(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        model.resend(id)
    }

    @objc private func openSettings() {
        onSettings()
    }

    @objc private func openAbout() {
        onAbout()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
