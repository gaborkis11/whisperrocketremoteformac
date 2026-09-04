import Foundation
import Testing
@testable import WRCore

@Suite("DictationText")
struct DictationTextTests {
    @Test("the host's closing newline is dropped")
    func trimsTrailingNewline() {
        #expect(DictationText.deliverable("Szia, Jarvis!\n") == "Szia, Jarvis!")
        #expect(DictationText.deliverable("Szia!\r\n\n  \t") == "Szia!")
    }

    @Test("leading whitespace survives — it may be part of the dictation")
    func keepsLeadingWhitespace() {
        #expect(DictationText.deliverable("  két szóköz\n") == "  két szóköz")
        #expect(DictationText.deliverable("\nelső sor") == "\nelső sor")
    }

    @Test("interior whitespace is untouched")
    func keepsInteriorWhitespace() {
        #expect(DictationText.deliverable("első sor\n\nmásodik sor\n") == "első sor\n\nmásodik sor")
    }

    @Test("nothing but whitespace means nothing was said")
    func emptyIsNil() {
        #expect(DictationText.deliverable("") == nil)
        #expect(DictationText.deliverable("\n") == nil)
        #expect(DictationText.deliverable("   \t\r\n ") == nil)
    }

    @Test("a body that is already clean comes back unchanged")
    func idempotent() {
        let text = "Ez már tiszta."
        #expect(DictationText.deliverable(text) == text)
        #expect(DictationText.deliverable(DictationText.deliverable(text)!) == text)
    }
}
