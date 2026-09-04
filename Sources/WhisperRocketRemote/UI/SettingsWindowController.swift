import AppKit
import SwiftUI

/// The settings window.
///
/// A plain `NSWindow`, not a SwiftUI `Settings` scene: the app's life cycle is
/// AppKit (`main.swift` + delegate), because the panel needs a window type
/// SwiftUI cannot express. The window is built on first use and reused, so
/// reopening it does not lose what was half-typed in the token field.
///
/// Not generic, for the same reason ``MenuBarUI`` is not: Swift 6.3.3's
/// optimiser segfaults on a generic class's implicit `deinit` in this module.
/// The concrete `SettingsView<Model>` is captured in a closure instead, which
/// keeps the type where it belongs — in the view — without a type parameter on
/// a class.
@MainActor
final class SettingsWindowController {
    private let makeContentView: () -> NSView
    private var window: NSWindow?

    init(makeContentView: @escaping () -> NSView) {
        self.makeContentView = makeContentView
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        if !window.isVisible {
            window.center()
        }
        // An accessory app has no Dock icon and never activates on its own, so
        // without this the settings window opens behind everything and cannot
        // be typed into.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }

    /// Draws the settings form into a bitmap, for the probes. A grouped `Form`
    /// is AppKit-backed and comes out blank from `ImageRenderer`, so this is the
    /// only way to actually look at it without a human at the screen.
    func capture() -> NSBitmapImageRep? {
        window?.contentView.flatMap(WindowCapture.image(of:))
    }

    private func makeWindow() -> NSWindow {
        let content = makeContentView()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: content.fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L.settingsWindowTitle
        window.contentView = content
        // Closing must not deallocate it: the same instance is reopened, so the
        // form keeps its state.
        window.isReleasedWhenClosed = false
        window.setContentSize(content.fittingSize)
        return window
    }
}
