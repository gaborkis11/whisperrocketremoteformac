import AppKit
import KeyboardShortcuts
import WRCore

/// The bridge between the recorder's `NSEvent.ModifierFlags` and WRCore's
/// Foundation-only `HotkeyModifiers`.
///
/// WRCore holds the rule — a dictation hotkey must include Command, or the keys
/// simply type into whatever app has focus (Option+letter produces an accented
/// character; it does not toggle anything) — and it holds it as a pure,
/// unit-tested function. This is the only place that translates AppKit's flags
/// into the vocabulary that function speaks, and it is deliberately
/// `nonisolated` so the recorder's validation closure needs no actor hop.
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
        case .missingCommand:
            // The reason is shown to the user by the recorder itself, so it has
            // to be a sentence, not a rule name.
            .disallow(reason: L.settingsHotkeyNeedsCommand)
        }
    }
}
