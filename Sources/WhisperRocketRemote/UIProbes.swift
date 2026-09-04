import AppKit
import KeyboardShortcuts
import SwiftUI

/// Command-line probes for the user interface.
///
/// None of them touches the microphone, the network or the user's settings:
///
/// * `--ui-probe [scenario] [--capture <dir>] [--seconds N]` builds the real
///   status item, the real panel and the real settings window against
///   ``MockPanelModel`` / ``MockSettingsModel`` and plays a scenario. This is
///   how the choreography was developed and how it is checked: not by reasoning
///   about the animation, by watching it.
/// * `--render-probe [directory]` writes a still of every stage, light and
///   dark, plus the Reduce Motion branch.
/// * `--icon-probe [directory]` renders the menu-bar rocket to PNG contact
///   sheets — idle, recording and badged, on a light and on a dark menu bar, at
///   1× through 8× — because an 18-point glyph cannot be judged any other way.
/// * `--l10n-probe` proves the `.lproj` bundles survived SwiftPM's `.process`
///   flattening and that both languages resolve every key.
/// * `--show-panel` is the odd one out: it opens the panel against the **real**
///   controller (see ``openPanelIfRequested(_:arguments:)``).
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

    /// Kept alive for the process's lifetime — the status item and the panel
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
        if let index = arguments.firstIndex(of: "--render-probe") {
            let directory = arguments.dropFirst(index + 1).first
            exit(runRenderProbe(directory: directory))
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

    // MARK: - --show-panel (the real controller)

    /// `--show-panel [--capture <dir>] [--seconds N]`
    ///
    /// Opens the panel against the **real** `DictationController`, a beat after
    /// launch, and optionally draws it to a PNG. It exists because the one thing
    /// `--ui-probe` cannot prove is the integration itself: the mock is not the
    /// controller, and clicking a menu-bar item is not something an automated
    /// check can do (`screencapture` and synthetic clicks both need permissions
    /// a probe must not ask a person for).
    ///
    /// It starts nothing: no microphone, no upload, no settings written.
    static func openPanelIfRequested(_ ui: MenuBarUI, arguments: [String] = CommandLine.arguments) {
        guard arguments.contains("--show-panel") else { return }
        let directory = value(named: "--capture", in: arguments)
        let quitAfter = seconds(named: "--seconds", in: arguments)

        Task { @MainActor in
            // F0's lesson again: the status item's button frame is wrong for the
            // first ~600 ms, and the panel hangs off that frame.
            try? await Task.sleep(for: .milliseconds(800))
            ui.showPanel()
            let frame = ui.panelFrameInScreen
            log("show-panel", "panel visible at \(Int(frame.minX)),\(Int(frame.minY)) "
                + "\(Int(frame.width))×\(Int(frame.height)) — real controller")

            log("show-panel", "status item: \(ui.statusItemDescription)")

            if let directory {
                try? await Task.sleep(for: .milliseconds(500))
                let url = URL(fileURLWithPath: directory)
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                write(ui.capturePanel(), to: url, named: "live-panel-real-controller.png", tag: "show-panel")
                // The glyph the menu bar is wearing at this exact moment — the
                // one thing the panel capture cannot show.
                write(
                    ui.captureStatusItemIcon(),
                    to: url,
                    named: "live-status-item-real-controller.png",
                    tag: "show-panel"
                )
            }

            if let quitAfter {
                try? await Task.sleep(for: .seconds(quitAfter))
                log("show-panel", "auto-quit")
                NSApp.terminate(nil)
            }
        }
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
        log("ui-probe", "click the menu-bar rocket to toggle the panel; “\(L.actionSettings)” opens the real settings window")

        Task { @MainActor in
            // F0's lesson: the status item's button frame is wrong for the first
            // ~600 ms of the process. Nothing may be positioned against it
            // before then, so the probe waits exactly as the real app waits for
            // a user's click.
            try? await Task.sleep(for: .milliseconds(700))
            ui.showPanel()
            panelModel.play(scenario)
            try? await Task.sleep(for: .milliseconds(400))
            let frame = ui.panelFrameInScreen
            log("ui-probe", "panel visible at \(Int(frame.minX)),\(Int(frame.minY)) "
                + "\(Int(frame.width))×\(Int(frame.height))")
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

        if let rep = ui.capturePanel(),
           let data = rep.representation(using: .png, properties: [:]) {
            let url = directory.appendingPathComponent("live-panel-\(scenario.rawValue).png")
            try? data.write(to: url, options: .atomic)
            log("ui-probe", "captured \(url.lastPathComponent) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
        } else {
            log("ui-probe", "panel capture FAILED")
        }

        ui.showSettings()
        Task { @MainActor in
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

    /// Renders the panel to PNG in every stage, in light and in dark.
    ///
    /// `screencapture` needs Screen Recording permission, which an automated
    /// check cannot grant itself; `ImageRenderer` needs nothing and draws the
    /// exact SwiftUI tree. What it cannot show is the vibrancy behind the panel
    /// and the animations — those are what the live `--ui-probe` is for — so the
    /// images are composited over the two backgrounds a `.hudWindow` material
    /// approximates, and read as layout and colour checks, not as the final look.
    private static func runRenderProbe(directory: String?) -> Int32 {
        let base = URL(fileURLWithPath: directory ?? FileManager.default.currentDirectoryPath)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let model = MockPanelModel(seedRecordings: false)
        let settingsModel = MockSettingsModel()
        var failures = 0

        for scenario in UIProbeScenario.allCases where scenario != .full {
            model.snapshot(scenario)
            for isDark in [false, true] {
                let name = "panel-\(scenario.rawValue)-\(isDark ? "dark" : "light").png"
                let view = PanelView(
                    model: model,
                    onSettings: {},
                    onQuit: {},
                    onContentSize: { _ in }
                )
                if write(view, to: base.appendingPathComponent(name), isDark: isDark) {
                    log("render-probe", "wrote \(name)")
                } else {
                    log("render-probe", "FAILED to render \(name)")
                    failures += 1
                }
            }
        }

        // Reduce Motion replaces the launch with a static rocket and the
        // system's own indeterminate bar. `accessibilityReduceMotion` is a
        // read-only environment value — a probe cannot fake it, and it must not
        // change the real system setting — but every stage takes the flag as a
        // plain parameter precisely so the branch can be rendered directly.
        let reducedMotionStages: [(String, AnyView)] = [
            ("reduced-motion-sending", AnyView(
                SendingStageView(attempt: 2, maxAttempts: 3, reduceMotion: true)
            )),
            ("reduced-motion-recording", AnyView(
                RecordingStageView(
                    level: 0.62,
                    peak: 0.78,
                    elapsed: 47,
                    countdown: 13,
                    hostReachable: false,
                    reduceMotion: true,
                    onStop: {}
                )
            )),
        ]
        for (name, stage) in reducedMotionStages {
            let framed = stage.frame(width: PanelMetrics.width - 2 * PanelMetrics.padding)
            if write(framed, to: base.appendingPathComponent("\(name).png"), isDark: false) {
                log("render-probe", "wrote \(name).png")
            } else {
                log("render-probe", "FAILED to render \(name).png")
                failures += 1
            }
        }

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

    private static func write(_ view: some View, to url: URL, isDark: Bool) -> Bool {
        // The backdrop is part of the rendered view, not composited afterwards:
        // the panel paints no background of its own (the vibrancy behind it
        // does), so without one the light and dark renders would both come out
        // on nothing.
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
            for key in ["status.recording", "idle.hint.shortcut", "countdown.autoStop"] {
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
        log("l10n-probe", "L.countdown(7) = \(L.countdown(7))")
        log("l10n-probe", "L.sendingAttempt(2, of: 3) = \(L.sendingAttempt(2, of: 3))")
        log("l10n-probe", "L.idleHint(⌘⇧Space) = \(L.idleHint(shortcut: "⌘⇧Space"))")
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
