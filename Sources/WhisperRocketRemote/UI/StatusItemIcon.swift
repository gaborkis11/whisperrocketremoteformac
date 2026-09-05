import AppKit

/// The menu-bar glyph: the app icon's rocket, drawn from ``SkyRocketGeometry``
/// instead of an asset.
///
/// Two reasons it is code and not a file: there is no "rocket" SF Symbol, and
/// the build has no asset catalog (no `actool` in the CLT-only build path).
/// Drawing it also means the Dock icon and the menu-bar glyph are the same
/// rocket rather than two pictures that drift apart.
///
/// Three flavours, and the differences matter:
/// * **template** — `isTemplate = true`, so AppKit tints it for a light or dark
///   menu bar and inverts it while the item is highlighted. This is what idle
///   looks like, and the only flavour that looks native. Apple's rule, followed
///   here: a menu-bar icon is monochrome unless it has something to say.
/// * **coloured** — the app *has* something to say: red while the microphone is
///   open, amber while an upload is in flight, a green flash when the text has
///   landed. This is the Linux tray's language, brought over deliberately. A
///   coloured image cannot be a template (a template has no colours, only
///   opacity), so it loses highlight inversion, and the ink is picked per menu
///   bar — the light-mode amber and green are darkened, because the bright ones
///   vanish against a near-white menu bar.
/// * **badged** — a red dot on the nose, for a recording that failed and is
///   waiting. Also not a template. The rocket underneath is painted in whatever
///   the current state's ink is — the menu bar's own colour when idle, resolved
///   from the status button's `effectiveAppearance` — so the composite reads
///   correctly in both modes.
nonisolated enum StatusItemIcon {
    /// What the rocket is saying, and therefore how it is painted.
    enum Style: Equatable, Sendable {
        /// Nothing is happening: monochrome, tinted by AppKit.
        case idle
        /// The microphone is open.
        case recording
        /// An upload is in flight.
        case sending
        /// The text landed. A flash, not a state — see ``doneFlash``.
        case done

        /// Whether AppKit paints this one (template) or we do.
        var isMonochrome: Bool { self == .idle }
    }

    /// 18 pt is the usual menu-bar glyph box on macOS; the art is inset inside it.
    static let size = NSSize(width: 18, height: 18)
    private static let inset: CGFloat = 1.5

    /// How long the green flash stays up before the icon goes quiet again.
    /// ``MenuBarUI`` owns the timer; a new phase always wins over it.
    static let doneFlash: Duration = .milliseconds(1500)

    // MARK: - Images

    /// The plain, tintable glyph. Idle, and nothing else.
    static func templateImage() -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            fillRocket(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = L.statusItemAccessibility
        return image
    }

    /// A rocket in the state's own colour. Never a template.
    ///
    /// - Parameter appearance: the *status button's* effective appearance, not
    ///   the app's — the menu bar can be dark while the app is light.
    static func colouredImage(style: Style, appearance: NSAppearance?) -> NSImage {
        // Resolved out here: the drawing handler may run off the main actor, so
        // it must only capture plain values.
        let ink = ink(for: style, isDark: isDark(appearance))

        let image = NSImage(size: size, flipped: false) { rect in
            color(ink).setFill()
            fillRocket(in: rect)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = accessibilityDescription(for: style)
        return image
    }

    /// Rocket plus the "a recording needs you" dot. Never a template.
    static func badgedImage(style: Style, appearance: NSAppearance?) -> NSImage {
        let isDark = isDark(appearance)
        let ink = ink(for: style, isDark: isDark)
        let badge = systemRedComponents()
        let haloIsBlack = isDark

        let image = NSImage(size: size, flipped: false) { rect in
            color(ink).setFill()
            fillRocket(in: rect)

            color(badge).setFill()
            // Top-right. The fins fill both bottom corners and the nose cone is
            // narrow, so this is the one corner where a dot covers nothing —
            // measured, not guessed: the earlier bottom-right placement ate the
            // right fin at 1×.
            let diameter = rect.width * 0.30
            let dot = NSRect(
                x: rect.maxX - diameter,
                y: rect.maxY - diameter,
                width: diameter,
                height: diameter
            )
            // A halo in the menu bar's own colour keeps the dot separate from
            // the rocket wherever they do touch — and from a red rocket, when a
            // recording is running while another one is still stuck.
            (haloIsBlack ? NSColor.black : NSColor.white).setStroke()
            let path = NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
            path.fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = L.statusItemAccessibilityFailed
        return image
    }

    static func image(style: Style, badged: Bool, appearance: NSAppearance?) -> NSImage {
        if badged {
            badgedImage(style: style, appearance: appearance)
        } else if style.isMonochrome {
            templateImage()
        } else {
            colouredImage(style: style, appearance: appearance)
        }
    }

    /// What the icon means, in words, for VoiceOver and the tooltip — because
    /// colour on its own is not a message everybody receives.
    static func accessibilityDescription(for style: Style) -> String {
        switch style {
        case .idle: L.statusItemAccessibility
        case .recording: "\(L.statusItemAccessibility) — \(L.statusRecording)"
        case .sending: "\(L.statusItemAccessibility) — \(L.capsuleSending)"
        case .done: "\(L.statusItemAccessibility) — \(L.statusDone)"
        }
    }

    // MARK: - Inspection

    /// An 18-point glyph cannot be judged at 18 points on a screenshot, and the
    /// menu bar itself cannot be photographed without a Screen Recording
    /// permission. So the icon is redrawn, larger, into a bitmap: same image,
    /// same tinting AppKit would apply, just big enough to see.
    static func magnified(
        _ image: NSImage,
        scale: Int,
        tint: NSColor?,
        background: NSColor?
    ) -> NSBitmapImageRep? {
        let side = Int(image.size.width) * scale
        let height = Int(image.size.height) * scale
        guard let sheet = bitmap(width: side, height: height) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)

        let rect = NSRect(x: 0, y: 0, width: side, height: height)
        background?.setFill()
        if background != nil { rect.fill() }

        let drawable = tint.flatMap { tinted(image, with: $0) } ?? image
        drawable.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        )
        return sheet
    }

    /// What AppKit does to a template image in the menu bar, done by hand: draw
    /// the glyph, then flood it with the menu bar's ink.
    static func tinted(_ image: NSImage, with color: NSColor) -> NSImage? {
        let size = image.size
        guard let rep = bitmap(width: Int(size.width * 8), height: Int(size.height * 8)) else { return nil }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(origin: .zero, size: size)
        image.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()

        let tinted = NSImage(size: size)
        tinted.addRepresentation(rep)
        return tinted
    }

    static func bitmap(width: Int, height: Int) -> NSBitmapImageRep? {
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    }

    // MARK: - Drawing

    /// The silhouette, filled with whatever colour is already set.
    private static func fillRocket(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.addPath(SkyRocketGeometry.silhouette(in: rect.insetBy(dx: inset, dy: inset)))
        // The porthole is a hole in the path the boolean subtraction produced,
        // and its winding is already right — non-zero keeps it open.
        context.fillPath(using: .winding)
    }

    // MARK: - Ink

    /// sRGB components, resolved before the drawing handler can capture them:
    /// `NSColor` is not `Sendable`, and a dynamic system colour would resolve
    /// against the *app's* appearance rather than the menu bar's anyway.
    private typealias Ink = (red: CGFloat, green: CGFloat, blue: CGFloat)

    private static func isDark(_ appearance: NSAppearance?) -> Bool {
        appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private static func color(_ ink: Ink) -> NSColor {
        NSColor(srgbRed: ink.red, green: ink.green, blue: ink.blue, alpha: 1)
    }

    private static func rgb(_ hex: UInt32) -> Ink {
        (
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255
        )
    }

    /// The state colours, per menu bar. The brand's amber is `#F5B82E`; the
    /// greens and reds are the system's.
    ///
    /// The dark-menu-bar values are those colours as they are. The light ones
    /// are darker, and that is not a preference: `#F5B82E` and a bright green
    /// sit at roughly 1.5:1 against a near-white menu bar — visible as a smudge,
    /// not as a colour. Each light value was picked to clear 3:1 (the contrast
    /// floor for a graphic that has to be *identified*, not just noticed) while
    /// staying recognisably the same hue. Checked, both ways, with
    /// `--icon-probe`.
    private static func ink(for style: Style, isDark: Bool) -> Ink {
        switch style {
        case .idle: isDark ? rgb(0xFFFFFF) : rgb(0x000000)
        case .recording: isDark ? rgb(0xFF453A) : rgb(0xE0281C)
        case .sending: isDark ? rgb(0xF5B82E) : rgb(0xB87400)
        case .done: isDark ? rgb(0x30D158) : rgb(0x0E8A32)
        }
    }

    private static func systemRedComponents() -> Ink {
        guard let srgb = NSColor.systemRed.usingColorSpace(.sRGB) else {
            return (1, 0.23, 0.19)
        }
        return (srgb.redComponent, srgb.greenComponent, srgb.blueComponent)
    }
}
