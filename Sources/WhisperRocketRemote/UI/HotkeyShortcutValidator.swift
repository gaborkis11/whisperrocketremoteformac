import AppKit
import KeyboardShortcuts
import WRCore

/// The bridge between the recorder's `NSEvent.ModifierFlags` and WRCore's
/// Foundation-only `HotkeyModifiers`.
///
/// WRCore holds the rule — a dictation hotkey needs at least one of ⌘/⌥/⌃,
/// because a bare letter (or ⇧+letter) would be typed into whatever app has
/// focus instead of toggling anything — and it holds it as a pure, unit-tested
/// function. This is the only place that translates AppKit's flags into the
/// vocabulary that function speaks, and it is deliberately `nonisolated` so the
/// recorder's validation closure needs no actor hop.
///
/// KeyboardShortcuts adds no restriction of its own here: its `isDisallowed`
/// check (which does demand ⌘ or ⌃ alongside ⌥) is gated on macOS 15.0/15.1
/// **and** a sandboxed app, and this app is neither — so ⌥W passes the
/// library's own gate and only has to pass ours.
nonisolated enum HotkeyShortcutValidator {
    static func modifiers(from flags: NSEvent.ModifierFlags) -> HotkeyModifiers {
        HotkeyModifiers(
            command: flags.contains(.command),
            shift: flags.contains(.shift),
            option: flags.contains(.option),
            control: flags.contains(.control),
            function: flags.contains(.function)
        )
    }

    static func validate(_ shortcut: KeyboardShortcuts.Shortcut) -> KeyboardShortcuts.ValidationResult {
        switch HotkeyValidation.validate(modifiers(from: shortcut.modifiers)) {
        case .valid:
            .allow
        case .missingPrimaryModifier:
            // The reason is shown to the user by the recorder itself, so it has
            // to be a sentence, not a rule name.
            .disallow(reason: L.settingsHotkeyNeedsModifier)
        }
    }
}
