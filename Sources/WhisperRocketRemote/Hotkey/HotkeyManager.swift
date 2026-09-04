import Foundation
import KeyboardShortcuts
import WRCore

extension KeyboardShortcuts.Name {
    static let toggleDictation = Self("toggleDictation", initial: .init(.space, modifiers: [.command, .shift]))
}

/// The global toggle, on top of KeyboardShortcuts' async event stream.
///
/// `onKeyUp` is deprecated in 3.x, and the stream is what replaces it. Key *up*
/// rather than key down: a held toggle key would otherwise auto-repeat into a
/// start/stop/start burst.
final class HotkeyManager {
    private var task: Task<Void, Never>?

    var isListening: Bool { task != nil }

    func start(onToggle: @escaping @MainActor () -> Void) {
        stop()
        task = Task {
            for await event in KeyboardShortcuts.events(for: .toggleDictation) where event == .keyUp {
                onToggle()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// The shortcut as configured right now, for the panel and for logging.
    var shortcut: KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: .toggleDictation)
    }

    /// The same rule the recorder UI enforces — at least one of ⌘/⌥/⌃ —
    /// applied to the shortcut that is actually stored. Anything less would be
    /// a plain keystroke that types into the focused app instead of toggling
    /// dictation. It goes through the recorder's own translation so the two can
    /// never drift apart.
    var isStoredShortcutValid: Bool {
        guard let shortcut else { return false }
        return HotkeyValidation.isValid(HotkeyShortcutValidator.modifiers(from: shortcut.modifiers))
    }
}
