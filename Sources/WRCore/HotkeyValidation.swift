import Foundation

/// The modifier keys of a hotkey, as a plain set.
///
/// Deliberately not `NSEvent.ModifierFlags` or a KeyboardShortcuts type:
/// WRCore is Foundation-only, so the recorder UI translates its own flags into
/// this set (`.init(command: flags.contains(.command), …)`) before asking for
/// a verdict.
public struct HotkeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = HotkeyModifiers(rawValue: 1 << 0)
    public static let shift = HotkeyModifiers(rawValue: 1 << 1)
    public static let option = HotkeyModifiers(rawValue: 1 << 2)
    public static let control = HotkeyModifiers(rawValue: 1 << 3)
    public static let function = HotkeyModifiers(rawValue: 1 << 4)

    public init(command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false, function: Bool = false) {
        var set = HotkeyModifiers(rawValue: 0)
        if command { set.insert(.command) }
        if shift { set.insert(.shift) }
        if option { set.insert(.option) }
        if control { set.insert(.control) }
        if function { set.insert(.function) }
        self = set
    }

    /// The modifiers that turn a key into a *command* rather than a character.
    ///
    /// Shift and Fn are missing on purpose: Shift only changes which character
    /// is produced (⇧W still types `W`), and Fn alone does not claim the key
    /// either.
    public static let primaryModifiers: HotkeyModifiers = [.command, .option, .control]
}

public enum HotkeyValidationResult: Equatable, Sendable {
    case valid
    /// Neither Command, Option nor Control is held, so the combination is a
    /// plain keystroke — `W` or `⇧W` would type a letter into whatever app has
    /// focus instead of toggling dictation.
    case missingPrimaryModifier
}

public enum HotkeyValidation {
    /// A dictation hotkey needs at least one of ⌘/⌥/⌃.
    ///
    /// **Why not "Command is mandatory", as an earlier version had it?** That
    /// rule was carried over from a project that watched key events with a
    /// passive tap, where Option+letter really did reach the focused app and
    /// type `∑` instead of toggling anything. Here the shortcut is handed to
    /// Carbon's `RegisterEventHotKey` (via KeyboardShortcuts), which *consumes*
    /// the event: a registered ⌥W never reaches the text field, so it types
    /// nothing. Option and Control are therefore as safe as Command, and ⌥W is
    /// a perfectly good dictation toggle.
    ///
    /// What stays refused is the case the mechanism cannot save us from: a bare
    /// letter, or Shift+letter, which the system would not let us claim as a
    /// global hotkey in any useful way — those are text, not commands. (Fn is
    /// likewise not enough on its own; KeyboardShortcuts strips it from the
    /// recorded modifiers anyway.)
    public static func validate(_ modifiers: HotkeyModifiers) -> HotkeyValidationResult {
        modifiers.isDisjoint(with: .primaryModifiers) ? .missingPrimaryModifier : .valid
    }

    public static func isValid(_ modifiers: HotkeyModifiers) -> Bool {
        validate(modifiers) == .valid
    }
}
