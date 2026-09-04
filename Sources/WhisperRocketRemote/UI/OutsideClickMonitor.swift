import AppKit

/// "Something was clicked that is not this window."
///
/// Mouse events only, and deliberately: a global *key* monitor would need the
/// Accessibility permission, and a window that closes when you click away has
/// no business asking for one. The consequence is that a window dismissed this
/// way stays open if you only ever use the keyboard, which is the trade the
/// panel has always made.
@MainActor
final class OutsideClickMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    var isRunning: Bool { globalMonitor != nil || localMonitor != nil }

    /// - Parameters:
    ///   - ownWindow: Clicks landing in this window are not "outside". Held
    ///     weakly: the monitor must never be the reason a window stays alive.
    ///   - onOutsideClick: Handed the click's location in screen coordinates,
    ///     which is the only coordinate space a global monitor can report in.
    func start(
        ignoring ownWindow: NSWindow?,
        onOutsideClick: @escaping @MainActor (NSPoint) -> Void
    ) {
        guard !isRunning else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        // Global: clicks in other apps.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { _ in
            MainActor.assumeIsolated {
                onOutsideClick(NSEvent.mouseLocation)
            }
        }

        // Local: clicks in our own other windows (the settings window).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak ownWindow] event in
            MainActor.assumeIsolated {
                if event.window !== ownWindow {
                    onOutsideClick(NSEvent.mouseLocation)
                }
            }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}
