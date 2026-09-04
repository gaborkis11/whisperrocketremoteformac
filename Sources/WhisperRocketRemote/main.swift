import AppKit

// --mic-probe is opt-in: the default launch path must never touch the microphone,
// so the TCC prompt is only ever raised with someone at the keyboard.
if CommandLine.arguments.contains("--mic-probe") {
    AudioProbe.run()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
