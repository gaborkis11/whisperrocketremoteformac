import Testing
@testable import WRCore

@Test func greetingIncludesName() {
    #expect(WRCore.greeting(for: "Gábor") == "Hello, Gábor!")
}
