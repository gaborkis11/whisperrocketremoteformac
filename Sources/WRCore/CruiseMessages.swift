import Foundation

/// The jokes the panel tells while the host is working.
///
/// Ported verbatim from the Linux app's `popup_phases.py`. Two things about
/// them are deliberate and must not be "fixed" later:
///
/// * **They are English in every language.** The animation is one piece and
///   speaks one voice (the user's call, 2026-09-03), so these are *not* in
///   `Localizable.strings` and `L` knows nothing about them. A Hungarian Mac
///   shows the same jokes a Hungarian Linux box does.
/// * **They are two pools upstream, one here.** The desktop app can tell the
///   local transcription apart from the AI cleanup and jokes about whichever
///   is running. This client only ever sees "the host is working", so the two
///   pools are merged: every joke still fits that one phase, and the pool is
///   twice as deep before it starts repeating.
///
/// It lives in WRCore rather than next to the view because that is the only
/// module `swift test` can reach, and ``maxCharacters`` is a rule worth
/// enforcing — a longer line runs into the panel's rounded corners.
public enum CruiseMessages {
    /// The panel is 300 pt wide and the joke sits centred at caption size;
    /// longer lines would truncate. `CruiseMessagesTests` holds every message
    /// to this, exactly as `tests/test_popup_phase.py` does upstream.
    public static let maxCharacters = 32

    /// About the local speech-to-text model — `popup_phases.PHASE_STT`.
    public static let transcription: [String] = [
        "Transcribing your thoughts...",
        "Converting speech to text...",
        "Crunching the soundwaves...",
        "Decoding your genius...",
        "Whisper is thinking...",
        "Making your cocktail...",
        "Brewing some magic...",
        "Summoning the words...",
        "Hold my coffee...",
        "Hearing you out, literally...",
        "Turning air into letters...",
        "Local GPU doing push-ups...",
        "Untangling your syllables...",
        "No cloud was harmed so far...",
        "Interpreting your wisdom...",
        "Patience, young padawan...",
        "Shazam! Almost ready...",
        "BRB, transcribing...",
    ]

    /// About the AI cleanup pass — `popup_phases.PHASE_AI`.
    public static let cleanup: [String] = [
        "Polishing your prose...",
        "Teaching commas some manners...",
        "Evicting the umms and errs...",
        "Proofreading at warp speed...",
        "Sanding the rough edges...",
        "Your swearing stays, promise...",
        "Punctuating, tastefully...",
        "Ironing out the sentences...",
        "Making it sound like you...",
        "Spell-checking the universe...",
        "Reading, not replying...",
        "Capital letters, assemble!...",
        "Trimming the filler words...",
        "Fixing what Whisper misheard...",
        "Almost worth framing...",
    ]

    /// The one pool this client draws from.
    public static let all: [String] = transcription + cleanup

    /// How long each joke stays up before the next one fades in.
    public static let interval: Duration = .milliseconds(2500)

    /// A random joke, never the one already on screen — `pick_message`.
    ///
    /// - Parameter previous: what the panel is showing right now, so the same
    ///   line cannot be picked twice in a row and read as a frozen animation.
    public static func next(after previous: String? = nil) -> String {
        var generator = SystemRandomNumberGenerator()
        return next(after: previous, using: &generator)
    }

    /// The seedable form, so the rule above can be *proved* rather than
    /// sampled: a test can drive it with a generator it controls.
    public static func next(
        after previous: String?,
        using generator: inout some RandomNumberGenerator
    ) -> String {
        let choices = all.filter { $0 != previous }
        // `all` is a non-empty literal, and dropping one element cannot empty
        // it, so both fallbacks are unreachable — they exist so this function
        // has no way to trap.
        return choices.randomElement(using: &generator) ?? all.first ?? ""
    }
}
