import Foundation

/// What to hand the clipboard once the host has answered.
public enum DictationText {
    /// Strips the trailing whitespace the host's verbatim body carries (its
    /// closing newline, mostly) and reports "nothing was said" as `nil`.
    ///
    /// Only the *trailing* end is touched: a leading space or newline can be
    /// part of what the user dictated, and this text is about to be pasted into
    /// the middle of somebody's document.
    ///
    /// `nil` is the signal never to touch the clipboard — a 2xx with an empty
    /// body would otherwise wipe whatever the user had copied, in exchange for
    /// nothing.
    public static func deliverable(_ raw: String) -> String? {
        var text = raw
        while let last = text.last, last.isWhitespace {
            text.removeLast()
        }
        return text.isEmpty ? nil : text
    }
}
