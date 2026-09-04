import Testing
@testable import WRCore

@Suite struct HotkeyValidationTests {
    @Test(arguments: [
        // Command, on its own and in every company.
        HotkeyModifiers.command,
        [.command, .shift],
        [.command, .option],
        [.command, .control],
        [.command, .shift, .option, .control],
        [.command, .function],
        // Option without Command: ⌥W is the shortcut this app is expected to
        // take. Carbon's RegisterEventHotKey swallows the event, so it toggles
        // dictation instead of typing “∑”.
        .option,
        [.option, .shift],
        [.option, .control],
        [.option, .function],
        // Control likewise.
        .control,
        [.control, .shift],
        [.control, .function],
    ] as [HotkeyModifiers])
    func anythingWithCommandOptionOrControlIsAccepted(modifiers: HotkeyModifiers) {
        #expect(HotkeyValidation.validate(modifiers) == .valid)
        #expect(HotkeyValidation.isValid(modifiers))
    }

    @Test(arguments: [
        // No modifier at all: a bare letter would just be typed.
        HotkeyModifiers(rawValue: 0),
        // Shift only changes which character is produced — ⇧W still types “W”.
        .shift,
        // Fn is not a command modifier either, and KeyboardShortcuts strips it
        // from a recorded shortcut anyway.
        .function,
        [.shift, .function],
    ] as [HotkeyModifiers])
    func plainTypingCombinationsAreRefused(modifiers: HotkeyModifiers) {
        #expect(HotkeyValidation.validate(modifiers) == .missingPrimaryModifier)
        #expect(!HotkeyValidation.isValid(modifiers))
    }

    @Test func theDefaultShortcutsModifiersPass() {
        // ⌘⇧Space, the shipped default.
        #expect(HotkeyValidation.isValid([.command, .shift]))
    }

    @Test func optionAloneIsTheRegressionThisRuleExistsFor() {
        // The rule used to demand Command, which made ⌥W impossible to record.
        #expect(HotkeyValidation.isValid(HotkeyModifiers(option: true)))
    }

    @Test func theBooleanInitializerMatchesTheOptionSet() {
        #expect(HotkeyModifiers(command: true, shift: true) == [.command, .shift])
        #expect(HotkeyModifiers() == HotkeyModifiers(rawValue: 0))
        #expect(HotkeyModifiers(option: true, control: true, function: true) == [.option, .control, .function])
    }

    @Test func primaryModifiersAreExactlyCommandOptionAndControl() {
        #expect(HotkeyModifiers.primaryModifiers == [.command, .option, .control])
        #expect(!HotkeyModifiers.primaryModifiers.contains(.shift))
        #expect(!HotkeyModifiers.primaryModifiers.contains(.function))
    }
}
