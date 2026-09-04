import AppKit

// --mic-probe is opt-in: the default launch path must never touch the microphone,
// so the TCC prompt is only ever raised with someone at the keyboard.
if CommandLine.arguments.contains("--mic-probe") {
    AudioProbe.run()
    exit(0)
}

// F2 audio probes (--devices, --synth-probe, --limits-probe, --record-probe).
// Only --record-probe opens the microphone; the rest are safe unattended.
if let code = Probes.runIfRequested() {
    exit(code)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
