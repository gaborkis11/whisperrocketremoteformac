import KeyboardShortcuts

/// Escape, and only while the microphone is open.
///
/// A **hard-coded** shortcut rather than a `Name`: this one is not the user's to
/// change, it must never be written to preferences, and it must not be listed in
/// the settings recorder (which would reject it anyway — the recorder insists on
/// a modifier, for the good reason that a plain key would otherwise type into
/// whatever app has focus).
///
/// That last point is exactly why the listener's *lifetime* is the whole
/// safety mechanism. `KeyboardShortcuts.events(for:)` registers the Carbon
/// hotkey when the stream is created and unregisters it when the task is
/// cancelled, and a registered hotkey swallows the keystroke system-wide. So the
/// stream exists for precisely as long as a recording does: start it when the
/// microphone opens, stop it the moment the phase leaves `.recording`, and
/// Escape goes back to closing dialogs everywhere else.
///
/// Key **down**, not up: cancelling should feel immediate, and a repeat is
/// harmless because `cancelRecording()` is guarded on there being something to
/// cancel.
final class EscapeCancelMonitor {
    private var task: Task<Void, Never>?

    var isListening: Bool { task != nil }

    func start(onCancel: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        task = Task {
            for await event in KeyboardShortcuts.events(for: Self.shortcut)
            where event == .keyDown {
                onCancel()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// No modifiers. `Shortcut(_:modifiers:)` takes an empty set by default and
    /// nothing validates it — the "needs a modifier" rule belongs to the
    /// recorder UI, not to the type.
    static let shortcut = KeyboardShortcuts.Shortcut(.escape)
}
