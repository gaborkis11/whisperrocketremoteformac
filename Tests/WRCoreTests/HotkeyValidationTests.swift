import Testing
@testable import WRCore

@Suite struct HotkeyValidationTests {
    @Test(arguments: [
        HotkeyModifiers.command,
        [.command, .shift],
        [.command, .option],
        [.command, .control],
        [.command, .shift, .option, .control],
        [.command, .function],
    ] as [HotkeyModifiers])
    func anyCombinationWithCommandIsAccepted(modifiers: HotkeyModifiers) {
        #expect(HotkeyValidation.validate(modifiers) == .valid)
        #expect(HotkeyValidation.isValid(modifiers))
    }

    @Test(arguments: [
        HotkeyModifiers(rawValue: 0),
        .option,                      // Option+letter types a character
        .shift,
        .control,
        [.option, .shift],
        [.control, .option, .shift],
        .function,
    ] as [HotkeyModifiers])
    func anythingWithoutCommandIsRefused(modifiers: HotkeyModifiers) {
        #expect(HotkeyValidation.validate(modifiers) == .missingCommand)
        #expect(!HotkeyValidation.isValid(modifiers))
    }

    @Test func theDefaultShortcutsModifiersPass() {
        // ⌘⇧Space, the shipped default.
        #expect(HotkeyValidation.isValid([.command, .shift]))
    }

    @Test func theBooleanInitializerMatchesTheOptionSet() {
        #expect(HotkeyModifiers(command: true, shift: true) == [.command, .shift])
        #expect(HotkeyModifiers() == HotkeyModifiers(rawValue: 0))
        #expect(HotkeyModifiers(option: true, control: true, function: true) == [.option, .control, .function])
    }
}
