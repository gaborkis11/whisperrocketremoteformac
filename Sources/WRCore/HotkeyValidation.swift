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
}

public enum HotkeyValidationResult: Equatable, Sendable {
    case valid
    /// Without Command the combination reaches the focused app as text —
    /// Option+letter types an accented character instead of toggling
    /// dictation — so the recorder refuses it.
    case missingCommand
}

public enum HotkeyValidation {
    public static func validate(_ modifiers: HotkeyModifiers) -> HotkeyValidationResult {
        modifiers.contains(.command) ? .valid : .missingCommand
    }

    public static func isValid(_ modifiers: HotkeyModifiers) -> Bool {
        validate(modifiers) == .valid
    }
}
