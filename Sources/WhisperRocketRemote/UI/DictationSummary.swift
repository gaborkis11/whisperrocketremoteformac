import Foundation
import WRNetwork

/// What the panel acknowledges after a successful dictation.
///
/// Note what is *not* here: the transcribed text. Showing it would turn a
/// glance into a read, and the text is already on the clipboard and (usually)
/// in the app the user was typing into. The character count is enough to
/// confirm "yes, that was your five minutes".
nonisolated struct DictationSummary: Equatable, Sendable {
    var characterCount: Int
    /// `.compose` means a trigger phrase turned the dictation into an answer
    /// rather than a transcript — worth saying, because the text will not match
    /// what was spoken.
    var mode: DictationMode
    var delivery: DeliveryOutcome

    init(characterCount: Int, mode: DictationMode = .transcript, delivery: DeliveryOutcome) {
        self.characterCount = characterCount
        self.mode = mode
        self.delivery = delivery
    }
}
