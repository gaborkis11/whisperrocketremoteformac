import AppKit
import KeyboardShortcuts
import SwiftUI
import WRCore
import WRNetwork

extension KeyboardShortcuts.Name {
    static let toggleDictation = Self("toggleDictation", default: .init(.space, modifiers: [.command, .shift]))
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()

        KeyboardShortcuts.onKeyUp(for: .toggleDictation) { [weak self] in
            self?.togglePanel()
        }

        SmokeReport.emit(shortcut: KeyboardShortcuts.getShortcut(for: .toggleDictation))

        if CommandLine.arguments.contains("--panel-probe") {
            runPanelProbe()
        }
    }

    /// Exercises the NSPanel + NSHostingView path without a human click.
    private func runPanelProbe() {
        Task { @MainActor in
            // The status item's window has no real frame until AppKit has laid it
            // out, so a probe fired straight from didFinishLaunching mispositions.
            try? await Task.sleep(for: .milliseconds(600))
            probePanelNow()
        }
    }

    private func probePanelNow() {
        showPanel()
        guard let panel else {
            print("[panel-probe] FAILED: no panel")
            return
        }
        if let button = statusItem?.button, let buttonWindow = button.window {
            print("[panel-probe] statusButton=\(buttonWindow.convertToScreen(button.convert(button.bounds, to: nil)))")
        }
        print("[panel-probe] visible=\(panel.isVisible) frame=\(panel.frame) "
            + "level=\(panel.level.rawValue) content=\(panel.contentView.map { "\(type(of: $0))" } ?? "nil") "
            + "isKeyWindow=\(panel.isKeyWindow) appActive=\(NSApp.isActive)")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            NSApp.terminate(nil)
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "WhisperRocket Remote")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        statusItem = item
    }

    @objc private func statusItemClicked() {
        togglePanel()
    }

    private func togglePanel() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        showPanel()
    }

    private func showPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrameOrigin(panelOrigin(for: panel))
        // orderFrontRegardless, not makeKeyAndOrderFront: the focused app must keep focus.
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 130),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let hosting = NSHostingView(rootView: SmokeView(report: SmokeReport.summary()))
        hosting.frame = panel.contentRect(forFrameRect: panel.frame)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }

    private func panelOrigin(for panel: NSPanel) -> NSPoint {
        guard let button = statusItem?.button, let buttonWindow = button.window else {
            return NSPoint(x: 100, y: 100)
        }
        let buttonInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        var x = buttonInScreen.midX - size.width / 2
        let y = buttonInScreen.minY - size.height - 6

        if let visible = buttonWindow.screen?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        return NSPoint(x: x, y: y)
    }
}
