import AppKit

/// The menu-bar glyph, drawn from ``RocketGeometry`` instead of an asset.
///
/// Two reasons it is code and not a file: there is no "rocket" SF Symbol, and
/// the build has no asset catalog (no `actool` in the CLT-only build path).
///
/// Two flavours, and the difference matters:
/// * **template** — `isTemplate = true`, so AppKit tints it for a light or dark
///   menu bar and inverts it while the item is highlighted. This is the normal
///   case and the only one that looks native.
/// * **badged** — a red dot on the tail fin, which cannot be a template (a
///   template image has no colours). The rocket is then painted in the colour
///   the menu bar itself is using, resolved from the status button's
///   `effectiveAppearance`, so the composite still reads correctly in both
///   modes. It loses highlight inversion; that is the price of a coloured
///   badge, and it is only worn while a recording actually needs attention.
nonisolated enum StatusItemIcon {
    /// How the rocket is drawn.
    enum Style: Equatable, Sendable {
        /// Idle: outline only.
        case outline
        /// Recording or sending: filled hull, so the state is obvious at a
        /// glance and not just "slightly different".
        case filled
    }

    /// 18 pt is the usual menu-bar glyph box on macOS; the art is inset inside it.
    static let size = NSSize(width: 18, height: 18)
    private static let inset: CGFloat = 1.5
    private static let lineWidth: CGFloat = 1.3

    /// The plain, tintable image. Use this whenever there is no badge.
    static func templateImage(style: Style) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.set()
            draw(style: style, in: rect, tint: .black)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = L.statusItemAccessibility
        return image
    }

    /// Rocket plus the "a recording needs you" dot. Never a template.
    ///
    /// - Parameter appearance: the *status button's* effective appearance, not
    ///   the app's — the menu bar can be dark while the app is light.
    static func badgedImage(style: Style, appearance: NSAppearance?) -> NSImage {
        let isDark = appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        // Resolved out here: the drawing handler may run off the main actor, so
        // it must only capture plain values.
        let tint = isDark ? NSColor.white : NSColor.black
        let badge = badgeComponents()

        let image = NSImage(size: size, flipped: false) { rect in
            draw(style: style, in: rect, tint: tint)
            NSColor(srgbRed: badge.red, green: badge.green, blue: badge.blue, alpha: 1).setFill()
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
            // the rocket wherever they do touch.
            (isDark ? NSColor.black : NSColor.white).setStroke()
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
        badged ? badgedImage(style: style, appearance: appearance) : templateImage(style: style)
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

    private static func draw(style: Style, in rect: NSRect, tint: NSColor) {
        let box = rect.insetBy(dx: inset, dy: inset)
        let hull = NSBezierPath()
        for contour in RocketGeometry.hull {
            hull.append(bezierPath(for: contour, in: box))
        }
        let window = NSBezierPath(ovalIn: RocketGeometry.rect(RocketGeometry.window, in: box, flipped: false))

        switch style {
        case .outline:
            tint.setStroke()
            hull.lineWidth = lineWidth
            hull.lineJoinStyle = .round
            hull.stroke()
            window.lineWidth = lineWidth
            window.stroke()
        case .filled:
            tint.setFill()
            // Even-odd punches the porthole back out of the solid hull, which is
            // what keeps the filled state recognisable as the same rocket.
            let solid = hull.copy() as? NSBezierPath ?? hull
            solid.append(window)
            solid.windingRule = .evenOdd
            solid.fill()
        }
    }

    private static func bezierPath(for elements: [RocketPathElement], in box: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        for element in elements {
            switch element {
            case .move(let point):
                path.move(to: RocketGeometry.point(point, in: box, flipped: false))
            case .line(let point):
                path.line(to: RocketGeometry.point(point, in: box, flipped: false))
            case .curve(let to, let control1, let control2):
                path.curve(
                    to: RocketGeometry.point(to, in: box, flipped: false),
                    controlPoint1: RocketGeometry.point(control1, in: box, flipped: false),
                    controlPoint2: RocketGeometry.point(control2, in: box, flipped: false)
                )
            case .close:
                path.close()
            }
        }
        return path
    }

    /// `NSColor` is not `Sendable`, so the badge colour is resolved to numbers
    /// before it can be captured by the drawing handler.
    private static func badgeComponents() -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        guard let srgb = NSColor.systemRed.usingColorSpace(.sRGB) else {
            return (1, 0.23, 0.19)
        }
        return (srgb.redComponent, srgb.greenComponent, srgb.blueComponent)
    }
}
