import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI
import WRCore

/// Command-line probes for the user interface.
///
/// None of them touches the microphone, the network or the user's settings:
///
/// * `--ui-probe [scenario] [--capture <dir>] [--seconds N]` builds the real
///   status item, the real capsule and the real settings window against
///   ``MockPanelModel`` / ``MockSettingsModel`` and plays a scenario. This is
///   how the choreography was developed and how it is checked: not by reasoning
///   about the animation, by watching it.
/// * `--render-probe [directory]` writes the settings form, light and dark.
/// * `--anim-probe [directory]` writes the capsule's sending stage at three
///   *chosen* instants, light and dark, plus the Reduce Motion branch — the only
///   way to show that a 60 fps animation actually animates without recording the
///   screen. It works because the whole scene is a pure function of a clock
///   (see ``CruiseInstant``), so a frame can be asked for by name.
/// * `--about-probe [directory]` writes the About window's contents, light and
///   dark.
/// * `--capsule-probe [directory]` writes every stage of the capsule HUD, over
///   a light and over a dark backdrop — the pill is always dark, so what the two
///   backdrops test is how it sits on top of what the user is actually looking
///   at.
/// * `--icon-probe [directory]` renders the menu-bar rocket to PNG contact
///   sheets — idle, recording and badged, on a light and on a dark menu bar, at
///   1× through 8× — because an 18-point glyph cannot be judged any other way.
/// * `--l10n-probe` proves the `.lproj` bundles survived SwiftPM's `.process`
///   flattening and that both languages resolve every key.
/// * `--escape-probe` asks macOS whether the bare Escape key can be registered
///   as a global hotkey at all — the one thing Escape-to-cancel depends on that
///   fails silently. Run it against a *second* copy of this app that is holding
///   Escape and it answers `-9878`, which is how the arming is proved end to end.
/// * `--show-settings` is the odd one out: it opens the settings window against
///   the **real** controller (see ``openSettingsIfRequested(_:arguments:)``).
///
/// Every image is drawn in-process, never with `screencapture` — that would ask
/// the person at the keyboard for a Screen Recording permission, which no
/// automated check has any business doing.
///
/// Wiring, in `AppDelegate.applicationDidFinishLaunching`, before the real
/// controller is installed:
///
/// ```swift
/// if UIProbes.runIfRequested(arguments: CommandLine.arguments) { return }
/// ```
///
/// The non-UI probes print and exit on their own; only `--ui-probe` returns
/// `true`, meaning "the UI is up, let the run loop have it".
enum UIProbes {
    /// The probe's own hotkey name, so recording a shortcut in the probe cannot
    /// overwrite the one the real app registered.
    static let probeShortcut = KeyboardShortcuts.Name(
        "uiProbeToggleDictation",
        initial: .init(.space, modifiers: [.command, .shift])
    )

    /// Kept alive for the process's lifetime — the status item and the capsule
    /// die with it.
    private nonisolated(unsafe) static var session: (ui: MenuBarUI, model: MockPanelModel)?

    /// - Returns: `true` when a UI probe is running and the caller should hand
    ///   over to the run loop.
    @discardableResult
    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        if let index = arguments.firstIndex(of: "--icon-probe") {
            let directory = arguments.dropFirst(index + 1).first
            exit(runIconProbe(directory: directory))
        }
        if arguments.contains("--l10n-probe") {
            exit(runLocalizationProbe())
        }
        if arguments.contains("--escape-probe") {
            exit(runEscapeProbe())
        }
        if let index = arguments.firstIndex(of: "--render-probe") {
            let directory = arguments.dropFirst(index + 1).first
            exit(runRenderProbe(directory: directory))
        }
        if let index = arguments.firstIndex(of: "--anim-probe") {
            let directory = arguments.dropFirst(index + 1).first
            exit(runAnimationProbe(directory: directory))
        }
        if let index = arguments.firstIndex(of: "--capsule-probe") {
            let directory = arguments.dropFirst(index + 1).first
            exit(runCapsuleProbe(directory: directory))
        }
        if let index = arguments.firstIndex(of: "--about-probe") {
            let directory = arguments.dropFirst(index + 1).first
            exit(runAboutProbe(directory: directory))
        }
        guard let index = arguments.firstIndex(of: "--ui-probe") else { return false }

        let argument = arguments.dropFirst(index + 1).first { !$0.hasPrefix("--") }
        let scenario: UIProbeScenario
        if let argument {
            guard let parsed = UIProbeScenario(argument: argument) else {
                log("ui-probe", "unknown scenario “\(argument)” — try one of: \(UIProbeScenario.allNames)")
                exit(2)
            }
            scenario = parsed
        } else {
            scenario = .default
        }

        startUI(
            scenario: scenario,
            autoQuitAfter: seconds(named: "--seconds", in: arguments),
            captureTo: value(named: "--capture", in: arguments),
            captureAfter: seconds(named: "--capture-after", in: arguments) ?? 1.6
        )
        return true
    }

    // MARK: - --show-settings (the real controller)

    /// `--show-settings [--capture <dir>] [--seconds N]`
    ///
    /// Opens the **real** settings window against the real model, closes it, and
    /// opens it again — capturing both. The second capture is the whole point:
    /// the window is reused, so the SwiftUI view's `.task` runs only on the
    /// first open, and a value the form reads from the system rather than from
    /// an observable property (the login item's status) used to freeze at
    /// whatever it was then. Two screenshots that disagree is exactly the bug;
    /// two that agree with `--login-status` is the fix.
    ///
    /// Reads only. It writes no settings and asks for no permission.
    static func openSettingsIfRequested(_ ui: MenuBarUI, arguments: [String] = CommandLine.arguments) {
        guard arguments.contains("--show-settings") else { return }
        let directory = value(named: "--capture", in: arguments)
        let quitAfter = seconds(named: "--seconds", in: arguments)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            let url = directory.map { URL(fileURLWithPath: $0) }
            if let url {
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }

            ui.showSettings()
            try? await Task.sleep(for: .milliseconds(700))
            log("show-settings", "first open — real controller")
            if let url {
                write(ui.captureSettings(), to: url, named: "settings-first-open.png", tag: "show-settings")
            }

            ui.closeSettings()
            try? await Task.sleep(for: .milliseconds(400))
            ui.showSettings()
            try? await Task.sleep(for: .milliseconds(700))
            log("show-settings", "reopened after close — this is the state that used to go stale")
            if let url {
                write(ui.captureSettings(), to: url, named: "settings-reopened.png", tag: "show-settings")
            }

            if let quitAfter {
                try? await Task.sleep(for: .seconds(quitAfter))
                log("show-settings", "auto-quit")
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - --ui-probe

    private static func startUI(
        scenario: UIProbeScenario,
        autoQuitAfter: Double?,
        captureTo captureDirectory: String? = nil,
        captureAfter: Double = 1.6
    ) {
        let panelModel = MockPanelModel()
        let settingsModel = MockSettingsModel()
        let ui = MenuBarUI(
            panelModel: panelModel,
            settingsModel: settingsModel,
            shortcutName: probeShortcut
        )
        session = (ui, panelModel)

        log("ui-probe", "scenario=\(scenario.rawValue) — status item installed")
        log("ui-probe", "click the menu-bar rocket for the menu; “\(L.actionSettings)” and “\(L.menuAbout)” open real windows")

        Task { @MainActor in
            // F0's lesson: the status item's button frame is wrong for the first
            // ~600 ms of the process. Nothing may be positioned against it
            // before then, so the probe waits exactly as the real app waits for
            // a user's click.
            try? await Task.sleep(for: .milliseconds(700))
            panelModel.play(scenario)
            try? await Task.sleep(for: .milliseconds(500))
            // Scenarios that start mid-flow (`sending`, `failed`, …) never pass
            // through `.recording`, which is the only thing that opens the
            // capsule in the app. The probe opens it by hand so those stages can
            // still be watched live.
            if !ui.isCapsuleVisible, scenario != .idle, scenario != .full {
                ui.showCapsule()
                try? await Task.sleep(for: .milliseconds(200))
                log("ui-probe", "capsule opened by the probe — this scenario never enters .recording")
            }
            if ui.isCapsuleVisible {
                let frame = ui.capsuleFrameInScreen
                log("ui-probe", "capsule visible at \(Int(frame.minX)),\(Int(frame.minY)) "
                    + "\(Int(frame.width))×\(Int(frame.height))")
            } else {
                log("ui-probe", "no capsule for this scenario — click the rocket for the menu")
            }
            // Armed says a task exists; the Carbon status says the task actually
            // got the key. `eventHotKeyExistsErr` here is the *good* answer.
            let carbon = takeEscapeHotKey()
            log("ui-probe", "escape listener armed=\(ui.isEscapeArmed), "
                + "carbon=\(carbon == OSStatus(eventHotKeyExistsErr) ? "held (eventHotKeyExistsErr)" : "\(carbon)")")
        }

        // `cancelled` is the one scenario the mock cannot play by itself: what
        // is worth watching is `MenuBarUI.cancel()`, the exact call Escape
        // makes, and the flash and fade that follow it.
        if scenario == .cancelled {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(max(captureAfter - 0.25, 0.5)))
                log("ui-probe", "cancel() — the Escape path, without a keystroke")
                ui.cancel()
            }
        }

        if let captureDirectory {
            Task { @MainActor in
                // Deliberately mid-flight: the launch animation is the thing
                // being checked, and its first frame is a blank sky.
                try? await Task.sleep(for: .seconds(captureAfter))
                capture(ui, scenario: scenario, into: URL(fileURLWithPath: captureDirectory))
            }
        }

        if let autoQuitAfter {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(autoQuitAfter))
                log("ui-probe", "auto-quit after \(autoQuitAfter) s")
                NSApp.terminate(nil)
            }
        }
    }

    private static func capture(
        _ ui: MenuBarUI,
        scenario: UIProbeScenario,
        into directory: URL
    ) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // The capsule first, while it is still the only thing on screen: this is
        // the live one, mid-animation, which no `ImageRenderer` still can be.
        if ui.isCapsuleVisible {
            write(
                ui.captureCapsule(),
                to: directory,
                named: "live-capsule-\(scenario.rawValue).png",
                tag: "ui-probe"
            )
        }
        // The glyph the menu bar is wearing at this exact moment — the one thing
        // no window capture can show.
        write(
            ui.captureStatusItemIcon(),
            to: directory,
            named: "live-status-item-\(scenario.rawValue).png",
            tag: "ui-probe"
        )

        Task { @MainActor in
            ui.showSettings()
            try? await Task.sleep(for: .milliseconds(600))
            guard let rep = ui.captureSettings(),
                  let data = rep.representation(using: .png, properties: [:])
            else {
                log("ui-probe", "settings capture FAILED")
                return
            }
            let url = directory.appendingPathComponent("live-settings.png")
            try? data.write(to: url, options: .atomic)
            log("ui-probe", "captured \(url.lastPathComponent) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
        }
    }

    // MARK: - --icon-probe

    private static func runIconProbe(directory: String?) -> Int32 {
        let base = URL(fileURLWithPath: directory ?? FileManager.default.currentDirectoryPath)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            log("icon-probe", "cannot create \(base.path): \(error.localizedDescription)")
            return 1
        }

        // The two menu-bar greys, sampled from the real thing: the light menu
        // bar is nearly white, the dark one nearly black, and a glyph has to
        // hold up on both.
        let sheets: [(name: String, isDark: Bool, background: NSColor)] = [
            ("icons-light.png", false, NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)),
            ("icons-dark.png", true, NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1)),
        ]

        for sheet in sheets {
            let url = base.appendingPathComponent(sheet.name)
            guard let data = contactSheet(isDark: sheet.isDark, background: sheet.background) else {
                log("icon-probe", "failed to render \(sheet.name)")
                return 1
            }
            do {
                try data.write(to: url, options: .atomic)
                log("icon-probe", "wrote \(url.path) (\(data.count) bytes)")
            } catch {
                log("icon-probe", "cannot write \(url.path): \(error.localizedDescription)")
                return 1
            }
        }
        log("icon-probe", "rows: idle (template), recording (template, filled), failed (badged composite)")
        log("icon-probe", "columns: 1×, 2×, 4×, 8× — 1× is what the menu bar actually shows")
        return 0
    }

    /// One sheet: three icon states down, four magnifications across.
    private static func contactSheet(isDark: Bool, background: NSColor) -> Data? {
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        let tint = isDark ? NSColor.white : NSColor.black
        let scales = [1, 2, 4, 8]
        let variants: [(label: String, image: NSImage, isTemplate: Bool)] = [
            ("idle", StatusItemIcon.templateImage(style: .outline), true),
            ("recording", StatusItemIcon.templateImage(style: .filled), true),
            ("badged", StatusItemIcon.badgedImage(style: .outline, appearance: appearance), false),
        ]

        let cell = 8 + 18 * 8 + 8
        let width = cell * scales.count
        let height = cell * variants.count
        guard let sheet = StatusItemIcon.bitmap(width: width, height: height) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)

        background.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        for (row, variant) in variants.enumerated() {
            for (column, scale) in scales.enumerated() {
                let side = 18 * scale
                let originX = column * cell + (cell - side) / 2
                // Row 0 at the top: the bitmap's origin is bottom-left.
                let originY = height - (row + 1) * cell + (cell - side) / 2
                let rect = NSRect(x: originX, y: originY, width: side, height: side)

                let drawable = variant.isTemplate
                    ? StatusItemIcon.tinted(variant.image, with: tint)
                    : variant.image
                drawable?.draw(
                    in: rect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1,
                    respectFlipped: true,
                    hints: [.interpolation: NSImageInterpolation.high.rawValue]
                )
            }
        }

        return sheet.representation(using: .png, properties: [:])
    }

    // MARK: - --render-probe

    /// Renders the settings form to PNG, light and dark.
    ///
    /// `screencapture` needs Screen Recording permission, which an automated
    /// check cannot grant itself; `ImageRenderer` needs nothing and draws the
    /// exact SwiftUI tree. What it cannot show is the live behaviour — that is
    /// what `--ui-probe` is for — so these read as layout and colour checks,
    /// not as the final look.
    ///
    /// The panel it used to photograph is gone: the menu-bar item opens an
    /// `NSMenu` now, and a menu is the system's picture, not ours.
    private static func runRenderProbe(directory: String?) -> Int32 {
        let base = URL(fileURLWithPath: directory ?? FileManager.default.currentDirectoryPath)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let settingsModel = MockSettingsModel()
        var failures = 0

        for isDark in [false, true] {
            let name = "settings-\(isDark ? "dark" : "light").png"
            let view = SettingsView(model: settingsModel, shortcutName: probeShortcut)
            if write(view, to: base.appendingPathComponent(name), isDark: isDark) {
                log("render-probe", "wrote \(name) (the shortcut recorder is an NSView and renders blank here)")
            } else {
                log("render-probe", "FAILED to render \(name)")
                failures += 1
            }
        }

        log("render-probe", failures == 0 ? "PASS" : "FAIL (\(failures) render(s))")
        return failures == 0 ? 0 : 1
    }

    // MARK: - --anim-probe

    /// Photographs the cruise animation, three frames at a time.
    ///
    /// A still of a moving picture proves nothing on its own — the honest
    /// question is *does it move*, and the honest answer is three stills of the
    /// same scene at three instants with the stars in three places. That is only
    /// possible because ``CruiseSceneView`` takes its instant as a parameter
    /// instead of reading a clock, so this probe can ask for frame 9 by name and
    /// get the same frame every run, on any machine.
    ///
    /// The instants are chosen, not sampled: they land on three different points
    /// of the flame's ten-frame sawtooth, so the exhaust is visibly short, long
    /// and mid-length across the set, while the starfield has moved 45 pt
    /// between the first two and most of a lap by the third.
    ///
    /// The scene now lives in the **capsule's** lane rather than in a panel
    /// stage, so what is photographed is the whole pill with the cruise inside
    /// it — which is the only place a person will ever see this animation.
    private static func runAnimationProbe(directory: String?) -> Int32 {
        let base = URL(fileURLWithPath: directory ?? FileManager.default.currentDirectoryPath)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let instants: [(name: String, instant: CruiseInstant)] = [
            ("t0.00", CruiseInstant(time: 0.00)),
            ("t0.15", CruiseInstant(time: 0.15)),
            ("t1.55", CruiseInstant(time: 1.55)),
        ]

        // The numbers behind the pictures, so the report can cite them rather
        // than claim them. The lane is the capsule's, not the panel's.
        let sceneSize = CGSize(
            width: CapsuleMetrics.laneWidth,
            height: CapsuleMetrics.laneHeight
        )
        for (name, instant) in instants {
            let frame = CruiseRocketGeometry.frame(at: instant.time)
            let flame = CruiseRocketGeometry.flameLength(atFrame: frame)
            let star = CruiseStarField.star(0, at: instant.time, in: sceneSize)
            log("anim-probe", String(
                format: "%@: frame %d, flame %.0f units, star 0 at x=%.1f y=%.1f r=%.1f",
                name, frame, flame, star.position.x, star.position.y, star.radius
            ))
        }

        let model = MockPanelModel(seedRecordings: false)
        model.snapshot(.sending)
        let flash = CapsuleCancelFlash()
        var failures = 0

        for (name, instant) in instants {
            for isDark in [false, true] {
                let file = "capsule-sending-\(name)-\(isDark ? "dark" : "light").png"
                let view = CapsuleView(
                    model: model,
                    flash: flash,
                    frozenStage: .sending,
                    frozenInstant: instant
                )
                if write(view, to: base.appendingPathComponent(file), isDark: isDark) {
                    log("anim-probe", "wrote \(file)")
                } else {
                    log("anim-probe", "FAILED to render \(file)")
                    failures += 1
                }
            }
        }

        // Reduce Motion goes through the real branch — no frozen instant — so
        // what is rendered is what the setting actually produces: the clock
        // stopped at `CruiseMetrics.stillInstant`.
        for isDark in [false, true] {
            let file = "capsule-sending-reduced-motion-\(isDark ? "dark" : "light").png"
            let view = CapsuleView(
                model: model,
                flash: flash,
                frozenStage: .sending,
                frozenReduceMotion: true
            )
            if write(view, to: base.appendingPathComponent(file), isDark: isDark) {
                log("anim-probe", "wrote \(file) — real Reduce Motion branch")
            } else {
                log("anim-probe", "FAILED to render \(file)")
                failures += 1
            }
        }

        log("anim-probe", failures == 0 ? "PASS — \(base.path)" : "FAIL (\(failures) render(s))")
        return failures == 0 ? 0 : 1
    }

    // MARK: - --about-probe

    /// Photographs the About window's contents, light and dark.
    ///
    /// Offscreen, like every other still here: the window itself is a plain
    /// `NSWindow`, and asking the screen for a picture of it would need a
    /// permission a probe has no business requesting. Run from inside the built
    /// bundle it shows the real icon and the real version; run from a bare
    /// `swift build` binary it shows the fallback rocket and "Version dev",
    /// which is the other half worth looking at.
    private static func runAboutProbe(directory: String?) -> Int32 {
        let base = URL(fileURLWithPath: directory ?? FileManager.default.currentDirectoryPath)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        log("about-probe", "bundle: \(Bundle.main.bundleURL.lastPathComponent)")
        log("about-probe", AboutView.versionLine)

        var failures = 0
        for isDark in [false, true] {
            let file = "about-\(isDark ? "dark" : "light").png"
            if write(AboutView(), to: base.appendingPathComponent(file), isDark: isDark) {
                log("about-probe", "wrote \(file)")
            } else {
                log("about-probe", "FAILED to render \(file)")
                failures += 1
            }
        }

        log("about-probe", failures == 0 ? "PASS — \(base.path)" : "FAIL (\(failures) render(s))")
        return failures == 0 ? 0 : 1
    }

    // MARK: - --capsule-probe

    /// Renders every stage of the capsule HUD, over a light and over a dark
    /// backdrop.
    ///
    /// The capsule is always dark, so the two backdrops are not a light/dark
    /// test of the pill — they are a test of the pill *against* the two kinds of
    /// thing it hangs over. What the light one has to prove is that a nearly
    /// black slab does not look like a hole punched in a white document; what
    /// the dark one has to prove is that the border and the top lip are still
    /// there when there is almost no contrast to carry them.
    ///
    /// The equalizer is frozen: a still cannot wait for a ring to fill itself
    /// in, and a snapshot of an empty one would show a flat line under a stage
    /// called "listening".
    ///
    /// It also photographs the **size candidates** — the same recording still at
    /// each scale under consideration, so the decision is made by looking rather
    /// than by reading numbers. Every size in ``CapsuleMetrics`` is a `static
    /// let` resolved once per process, so a second size means a second process:
    /// the run below re-launches this binary with `WR_CAPSULE_SCALE` set, and
    /// each child renders exactly one still and exits.
    private static func runCapsuleProbe(directory: String?) -> Int32 {
        let base = URL(fileURLWithPath: directory ?? FileManager.default.currentDirectoryPath)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let model = MockPanelModel(seedRecordings: false)
        let flash = CapsuleCancelFlash()
        let waveform = syntheticWaveform()

        // A child run: one size still, and nothing else.
        if CapsuleMetrics.scaleOverride != nil {
            return renderSizeStill(model: model, flash: flash, waveform: waveform, into: base)
                ? 0
                : 1
        }

        let stills: [(name: String, scenario: UIProbeScenario, stage: CapsuleStage)] = [
            ("recording", .recording, .recording),
            ("recording-stored", .storedMode, .recording),
            ("recording-countdown", .countdown, .recording),
            ("sending", .sending, .sending),
            ("done-typed", .done, .done),
            ("done-clipboard", .clipboardOnly, .done),
            ("failed", .failed, .failed),
            ("cancelled", .cancelled, .cancelled),
        ]

        var failures = 0
        for still in stills {
            model.snapshot(still.scenario)
            for isDark in [false, true] {
                let file = "capsule-\(still.name)-\(isDark ? "dark" : "light").png"
                let view = CapsuleView(
                    model: model,
                    flash: flash,
                    frozenStage: still.stage,
                    frozenHistory: waveform
                )
                if write(view, to: base.appendingPathComponent(file), isDark: isDark) {
                    log("capsule-probe", "wrote \(file)")
                } else {
                    log("capsule-probe", "FAILED to render \(file)")
                    failures += 1
                }
            }
        }

        log("capsule-probe", "shipped: \(CapsuleMetrics.summary)")
        failures += renderSizeCandidates(model: model, flash: flash, waveform: waveform, into: base)

        log("capsule-probe", failures == 0 ? "PASS — \(base.path)" : "FAIL (\(failures) render(s))")
        return failures == 0 ? 0 : 1
    }

    /// The sizes on the table, largest first, with the shipped one last so the
    /// log ends on what is actually installed. `0.45` is what F6.1 shipped —
    /// keeping it here is what makes the step to 50 % visible side by side.
    private static let capsuleSizeCandidates: [Double] = [0.60, 0.45, CapsuleMetrics.defaultScale]

    /// One recording still per candidate size, on the light backdrop only: what
    /// is being compared here is how much room the pill takes, and two backdrops
    /// of the same answer help nobody.
    private static func renderSizeCandidates(
        model: MockPanelModel,
        flash: CapsuleCancelFlash,
        waveform: WaveformHistory,
        into base: URL
    ) -> Int {
        var failures = 0
        for candidate in capsuleSizeCandidates {
            if abs(candidate - CapsuleMetrics.scale) < 0.0001 {
                // The size this process was already built at.
                if !renderSizeStill(model: model, flash: flash, waveform: waveform, into: base) {
                    failures += 1
                }
            } else if !renderSizeStillInChild(scale: candidate, into: base) {
                failures += 1
            }
        }
        return failures
    }

    private static func renderSizeStill(
        model: MockPanelModel,
        flash: CapsuleCancelFlash,
        waveform: WaveformHistory,
        into base: URL
    ) -> Bool {
        model.snapshot(.recording)
        let file = "capsule-size-\(CapsuleMetrics.scalePercent)-light.png"
        let view = CapsuleView(
            model: model,
            flash: flash,
            frozenStage: .recording,
            frozenHistory: waveform
        )
        guard write(view, to: base.appendingPathComponent(file), isDark: false) else {
            log("capsule-probe", "FAILED to render \(file)")
            return false
        }
        log("capsule-probe", "wrote \(file) — \(CapsuleMetrics.summary)")
        return true
    }

    /// Re-launches this binary at another scale. The child inherits stdout, so
    /// its one line lands in this run's log in order.
    private static func renderSizeStillInChild(scale: Double, into base: URL) -> Bool {
        let executable = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0])

        let process = Process()
        process.executableURL = executable
        process.arguments = ["--capsule-probe", base.path]
        var environment = ProcessInfo.processInfo.environment
        environment[CapsuleMetrics.scaleOverrideKey] = String(scale)
        process.environment = environment

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log("capsule-probe", "could not launch a child at scale \(scale) — "
                + error.localizedDescription)
            return false
        }
        guard process.terminationStatus == 0 else {
            log("capsule-probe", "the child at scale \(scale) exited \(process.terminationStatus)")
            return false
        }
        return true
    }

    /// The mock meter's own speech envelope, run forward at the capsule's 20 Hz
    /// sampling rate, so a still shows the shape a voice actually makes rather
    /// than a sine wave.
    private static func syntheticWaveform() -> WaveformHistory {
        var history = WaveformHistory()
        var level = 0.0
        let dt = 1.0 / 20.0
        // Three times round the ring, so every slot holds a settled value.
        for step in 0..<(history.capacity * 3) {
            let time = Double(step) * dt
            let syllable = 0.5 + 0.5 * sin(time * 11)
            let phrase = 0.5 + 0.5 * sin(time * 0.7 + 1.1)
            let breath = phrase < 0.12 ? 0.0 : 1.0
            let target = min(1, max(0, 0.22 + 0.7 * syllable * phrase * breath))
            let tau = target > level ? 0.03 : 0.25
            level += (target - level) * (1 - exp(-dt / tau))
            history.push(level)
        }
        return history
    }

    // MARK: - --escape-probe

    /// The one thing about Escape-to-cancel that cannot be reasoned about:
    /// whether macOS will let this process take the bare Escape key as a global
    /// hotkey. `KeyboardShortcuts` registers through the same Carbon call but
    /// keeps the result private, and its failure is silent.
    ///
    /// Run on its own — before anything else is installed — a `noErr` says the
    /// registration this feature depends on works here. Run *while the Escape
    /// listener is armed* (which is what `--ui-probe` does), the same call is
    /// expected to come back `eventHotKeyExistsErr`, and that is the proof the
    /// listener really reached Carbon rather than merely starting a task.
    ///
    /// It cannot answer "does another app hold Escape": Carbon's uniqueness
    /// check is per event-dispatcher target, so two processes can each hold the
    /// same combination. That question stays a live-test question.
    private static func runEscapeProbe() -> Int32 {
        let status = takeEscapeHotKey()
        if status == noErr {
            log("escape-probe", "RegisterEventHotKey(kVK_Escape, no modifiers) = noErr — "
                + "the bare Escape key can be registered by this process")
            log("escape-probe", "PASS")
            return 0
        }

        log("escape-probe", "RegisterEventHotKey(kVK_Escape, no modifiers) = \(status)"
            + (status == OSStatus(eventHotKeyExistsErr) ? " (eventHotKeyExistsErr)" : ""))
        log("escape-probe", "FAIL — Escape-to-cancel would be silently dead; "
            + "fall back to a Name with enable/disable, or the capsule's stop button")
        return 1
    }

    /// Registers the bare Escape hotkey and lets it go again, returning what the
    /// system said. `eventHotKeyExistsErr` means something in *this process*
    /// already holds it.
    private static func takeEscapeHotKey() -> OSStatus {
        var reference: EventHotKeyRef?
        // 'WRRE', so a stray registration is recognisable in a crash log.
        let identifier = EventHotKeyID(signature: OSType(0x5752_5245), id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,
            identifier,
            GetEventDispatcherTarget(),
            0,
            &reference
        )
        if let reference { UnregisterEventHotKey(reference) }
        return status
    }

    // MARK: - Shared rendering

    private static func write(_ view: some View, to url: URL, isDark: Bool) -> Bool {
        // The backdrop is part of the rendered view, not composited afterwards:
        // the views here paint no background of their own, so without one the
        // light and dark renders would both come out on nothing.
        let backdrop = isDark ? Color(white: 0.17) : Color(white: 0.95)

        let renderer = ImageRenderer(
            content: view
                .environment(\.colorScheme, isDark ? .dark : .light)
                .padding(16)
                .background(backdrop)
        )
        renderer.scale = 2

        var data: Data?
        // `NSColor`-backed styles resolve against the *drawing* appearance, not
        // the SwiftUI environment, so both have to be switched together or the
        // dark render comes out with light separators.
        NSAppearance(named: isDark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            guard let cgImage = renderer.cgImage else { return }
            data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        }

        guard let data else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    // MARK: - --l10n-probe

    /// F0 measured that `.process("Resources")` flattens subdirectories — the
    /// `Sounds/` folder vanished and its files landed in the bundle root. This
    /// proves the `.lproj` directories are the exception (SwiftPM treats them as
    /// localizations, not as folders) and that both languages actually resolve.
    private static func runLocalizationProbe() -> Int32 {
        let bundle = L.bundle
        log("l10n-probe", "bundle: \(bundle.bundleURL.lastPathComponent)")
        log("l10n-probe", "localizations: \(bundle.localizations.sorted().joined(separator: ", "))")
        log("l10n-probe", "development region: \(bundle.developmentLocalization ?? "<none>")")
        log("l10n-probe", "preferred: \(bundle.preferredLocalizations.joined(separator: ", "))")
        log("l10n-probe", "system language order: \(Locale.preferredLanguages.joined(separator: ", "))")
        // What the bundle would pick on a Hungarian-first Mac. This is the
        // selection the app relies on: there is no in-app language switch.
        let hungarianFirst = Bundle.preferredLocalizations(
            from: bundle.localizations,
            forPreferences: ["hu-HU", "en-US"]
        )
        log("l10n-probe", "would pick on a hu-first Mac: \(hungarianFirst.joined(separator: ", "))")

        var failures = 0
        var keySets: [String: Set<String>] = [:]

        for language in ["en", "hu"] {
            guard let path = bundle.path(forResource: language, ofType: "lproj"),
                  let languageBundle = Bundle(path: path) else {
                log("l10n-probe", "FAIL: no \(language).lproj inside the resource bundle")
                failures += 1
                continue
            }
            guard let stringsURL = languageBundle.url(forResource: "Localizable", withExtension: "strings"),
                  let table = NSDictionary(contentsOf: stringsURL) as? [String: String] else {
                log("l10n-probe", "FAIL: \(language)/Localizable.strings is missing or unreadable")
                failures += 1
                continue
            }
            keySets[language] = Set(table.keys)
            log("l10n-probe", "\(language): \(table.count) keys")

            // A sample that exercises a plain key, a %@ key and a %d key.
            for key in ["status.recording", "menu.lastRecord", "capsule.countdown"] {
                let value = languageBundle.localizedString(forKey: key, value: "<missing>", table: nil)
                log("l10n-probe", "  \(language)/\(key) = \(value)")
                if value == "<missing>" { failures += 1 }
            }
        }

        if let english = keySets["en"], let hungarian = keySets["hu"] {
            let missingInHungarian = english.subtracting(hungarian).sorted()
            let missingInEnglish = hungarian.subtracting(english).sorted()
            if missingInHungarian.isEmpty, missingInEnglish.isEmpty {
                log("l10n-probe", "key sets match exactly (\(english.count) keys)")
            } else {
                failures += missingInHungarian.count + missingInEnglish.count
                log("l10n-probe", "FAIL: missing from hu: \(missingInHungarian.joined(separator: ", "))")
                log("l10n-probe", "FAIL: missing from en: \(missingInEnglish.joined(separator: ", "))")
            }
        }

        // And the path the app itself takes: the `L` accessors against the
        // bundle's own preferred localization.
        log("l10n-probe", "L.statusRecording = \(L.statusRecording)")
        log("l10n-probe", "L.capsuleCountdown(7) = \(L.capsuleCountdown(7))")
        log("l10n-probe", "L.capsuleAttempt(2, of: 3) = \(L.capsuleAttempt(2, of: 3))")
        log("l10n-probe", "L.menuLastRecord = \(L.menuLastRecord("0:42", L.recordingStatusSent))")
        log("l10n-probe", "L.menuAbout = \(L.menuAbout)")
        if L.statusRecording == "status.recording" {
            log("l10n-probe", "FAIL: L returned the key — the bundle did not resolve")
            failures += 1
        }

        log("l10n-probe", failures == 0 ? "PASS" : "FAIL (\(failures) problem(s))")
        return failures == 0 ? 0 : 1
    }

    // MARK: - Shared

    /// Writes one captured bitmap, saying so either way — a probe that fails
    /// silently is worse than no probe.
    @discardableResult
    private static func write(
        _ rep: NSBitmapImageRep?,
        to directory: URL,
        named name: String,
        tag: String
    ) -> Bool {
        guard let rep, let data = rep.representation(using: .png, properties: [:]) else {
            log(tag, "\(name): capture FAILED")
            return false
        }
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            log(tag, "captured \(url.path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
            return true
        } catch {
            log(tag, "\(name): could not be written — \(error.localizedDescription)")
            return false
        }
    }

    private static func value(named flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        return arguments.dropFirst(index + 1).first { !$0.hasPrefix("--") }
    }

    private static func seconds(named flag: String, in arguments: [String]) -> Double? {
        value(named: flag, in: arguments).flatMap(Double.init)
    }

    private static func log(_ tag: String, _ message: String) {
        print("[\(tag)] \(message)")
        fflush(stdout)
    }
}
