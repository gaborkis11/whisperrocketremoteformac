import AppKit
import SwiftUI

/// The About window.
///
/// The same shape as ``SettingsWindowController``: a plain titled, closable
/// `NSWindow`, built on first use and reused afterwards, because the app's life
/// cycle is AppKit and an accessory app has to activate itself or the window
/// opens behind everything.
///
/// Simpler than the settings one in the two ways that matter: the content is
/// static, so there is no `onShow` hook to refresh anything, and it takes no
/// model, so there is no type parameter to keep off the class.
@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        if !window.isVisible {
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let content = NSHostingView(rootView: AboutView())
        content.sizingOptions = [.minSize, .intrinsicContentSize]
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: content.fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L.menuAbout
        window.contentView = content
        // Closing must not deallocate it — the same instance is reopened.
        window.isReleasedWhenClosed = false
        window.setContentSize(content.fittingSize)
        return window
    }
}
