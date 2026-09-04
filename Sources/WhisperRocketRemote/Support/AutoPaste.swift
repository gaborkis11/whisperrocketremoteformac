import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Clipboard delivery, plus the synthesised ⌘V that types the text into
/// whatever had focus when the recording started.
///
/// Two separate trust checks on purpose: ``requestTrust()`` raises the system
/// prompt and belongs to the Settings switch, while ``isTrusted`` never prompts
/// and is what every paste re-checks — the grant can be revoked between the
/// switch and the dictation.
enum AutoPaste {
    /// How long the target app needs to see the new pasteboard contents before
    /// ⌘V will pick them up.
    static let pasteboardPropagationDelay: Duration = .milliseconds(80)

    /// Prompt-free. Safe to call on every delivery.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Raises the Accessibility prompt. Only the Settings UI calls this, when
    /// the user turns auto-typing on.
    @discardableResult
    static func requestTrust() -> Bool {
        // Spelled out rather than read from `kAXTrustedCheckOptionPrompt`: that
        // symbol is imported as a mutable global, which Swift 6 refuses to
        // touch from a concurrent context. The string value is API.
        let options = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Opens the Accessibility pane, for the case where the prompt was already
    /// answered once and macOS will not show it again.
    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// The clipboard write, which happens for every successful dictation
    /// whether or not typing is enabled. Returns the pasteboard's change count
    /// so a caller can prove the write landed.
    @discardableResult
    static func copyToPasteboard(_ text: String) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    /// Synthesises ⌘V. Returns false when the event could not be built — a
    /// missing Accessibility grant does *not* show up here, it simply makes the
    /// posted event go nowhere, which is why the caller checks `isTrusted` first.
    @discardableResult
    static func postCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let key = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return false }
        // Set, not OR'd: whatever the user is still physically holding must not
        // turn ⌘V into ⇧⌘V.
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }

    /// The app that will receive the paste. Our own app is an accessory and
    /// never becomes frontmost, so this is always somebody else.
    static var frontmostBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
