#!/usr/bin/env swift
//
//  make-appicon.swift — the WhisperRocket app icon, drawn rather than painted.
//
//  Usage: swift scripts/make-appicon.swift <out.iconset>
//
//  Every size is rendered from the same vector description into its own
//  bitmap, so a 16-pixel icon is *drawn at 16 pixels* instead of being a 1024
//  master squeezed down by sips — which is what turns a thin rocket into grey
//  mush. The small sizes also drop the details that cannot survive them (see
//  `Detail`), which is the other half of what an icon set is for.
//
//  The macOS grid, straight from Apple's template: a 1024 transparent canvas,
//  an 824×824 rounded square centred in it (100 px of air on every side), and a
//  soft shadow under that square. The system does not mask app icons — the file
//  carries its own shape and its own margin, and an icon that fills the canvas
//  looks oversized next to every other one in the Dock.
//
//  SwiftUI is imported for exactly one thing: `RoundedRectangle(style:
//  .continuous)` is Apple's own squircle geometry, and hand-rolling a
//  continuous corner is how you get an icon that is subtly the wrong shape.
//

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - The design

/// Every number in the artwork, in the 1024-point canvas the icon is designed
/// in. Nothing below this line invents a value.
enum Sky {
    static let canvas: CGFloat = 1024
    /// The rounded square: 824 across, 100 of margin on each side.
    static let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let cornerRadius: CGFloat = 185

    // The shadow that separates the plate from a light desktop.
    static let shadowOffset = CGSize(width: 0, height: -12)
    static let shadowBlur: CGFloat = 20
    static let shadowAlpha: CGFloat = 0.25

    /// Background gradient, top to bottom: #5E8CFF → #3453E6.
    static let skyTop = rgb(0x5E8CFF)
    static let skyBottom = rgb(0x3453E6)
    /// The porthole: a darker blue than the sky under it, so it reads as glass.
    static let porthole = rgb(0x2F4BD6)

    /// Star field, as fractions of the plate — x from the left, y from the
    /// **top**, radius as a fraction of the plate's width.
    static let stars: [(x: CGFloat, y: CGFloat, r: CGFloat, alpha: CGFloat)] = [
        (0.15, 0.20, 0.0140, 0.45),
        (0.83, 0.32, 0.0090, 0.35),
        (0.22, 0.78, 0.0105, 0.30),
        (0.80, 0.85, 0.0070, 0.40),
    ]

    /// The rocket stands 62 % of the plate tall, centred on it.
    static let rocketHeightFraction: CGFloat = 0.62

    static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// How much of the artwork survives at a given pixel size.
///
/// Thresholds are not taste, they are arithmetic done on the rendered PNGs: a
/// star is 0.36 px across on a 32-pixel icon, and a 0.36 px grey dot is not a
/// star, it is dirt. The flame turns into a smudge under the nozzle at the same
/// size. And at 16 px the hull is barely 2.5 px wide, so the porthole stops
/// being a window and becomes a hole punched through the rocket — dropped, and
/// the rocket grown a little to earn back the pixels the detail cost.
enum Detail {
    case full        // 128 px and up: everything
    case reduced     // 64 px: no stars, the flame still reads
    case small       // 32 px: hull, fins, nozzle, porthole
    case tiny        // 16 px: a clean white rocket, nothing else

    init(pixels: Int) {
        switch pixels {
        case 128...: self = .full
        case 64...: self = .reduced
        case 32...: self = .small
        default: self = .tiny
        }
    }

    var showsStars: Bool { self == .full }
    var showsFlame: Bool { self == .full || self == .reduced }
    var showsPorthole: Bool { self != .tiny }

    /// The rocket's height as a fraction of the plate. Slightly taller once the
    /// detail is gone, so the silhouette still carries the icon.
    var rocketHeightFraction: CGFloat { self == .tiny ? 0.70 : Sky.rocketHeightFraction }
}

// MARK: - The rocket, in its own 100 × 150 viewBox

/// The rocket is described once, in SVG-style coordinates (x 0…100, y 0…150,
/// **y down**), and mapped into whatever box it has to fill. The menu-bar glyph
/// in `Sources/WhisperRocketRemote/UI/SkyRocketGeometry.swift` is the same
/// drawing in the same numbers — change one, change the other.
enum Rocket {
    static let viewBox = CGSize(width: 100, height: 150)

    /// Hull: nose, body, and the flat tail the nozzle hangs off.
    static func hull(_ t: CGAffineTransform) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 50, y: 10), transform: t)
        p.addCurve(to: CGPoint(x: 73, y: 74), control1: CGPoint(x: 66, y: 26), control2: CGPoint(x: 73, y: 50), transform: t)
        p.addCurve(to: CGPoint(x: 66, y: 106), control1: CGPoint(x: 73, y: 88), control2: CGPoint(x: 70, y: 99), transform: t)
        p.addLine(to: CGPoint(x: 34, y: 106), transform: t)
        p.addCurve(to: CGPoint(x: 27, y: 74), control1: CGPoint(x: 30, y: 99), control2: CGPoint(x: 27, y: 88), transform: t)
        p.addCurve(to: CGPoint(x: 50, y: 10), control1: CGPoint(x: 27, y: 50), control2: CGPoint(x: 34, y: 26), transform: t)
        p.closeSubpath()
        return p
    }

    static func leftFin(_ t: CGAffineTransform) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 30, y: 84), transform: t)
        p.addCurve(to: CGPoint(x: 14, y: 114), control1: CGPoint(x: 20, y: 92), control2: CGPoint(x: 15, y: 103), transform: t)
        p.addCurve(to: CGPoint(x: 33, y: 106), control1: CGPoint(x: 20, y: 110), control2: CGPoint(x: 27, y: 107), transform: t)
        p.closeSubpath()
        return p
    }

    static func rightFin(_ t: CGAffineTransform) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 70, y: 84), transform: t)
        p.addCurve(to: CGPoint(x: 86, y: 114), control1: CGPoint(x: 80, y: 92), control2: CGPoint(x: 85, y: 103), transform: t)
        p.addCurve(to: CGPoint(x: 67, y: 106), control1: CGPoint(x: 80, y: 110), control2: CGPoint(x: 73, y: 107), transform: t)
        p.closeSubpath()
        return p
    }

    static func nozzle(_ t: CGAffineTransform) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 42, y: 106), transform: t)
        p.addLine(to: CGPoint(x: 58, y: 106), transform: t)
        p.addLine(to: CGPoint(x: 55, y: 116), transform: t)
        p.addLine(to: CGPoint(x: 45, y: 116), transform: t)
        p.closeSubpath()
        return p
    }

    static func window(_ t: CGAffineTransform) -> CGPath {
        CGPath(ellipseIn: CGRect(x: 38, y: 50, width: 24, height: 24), transform: [t])
    }

    static func flame(_ t: CGAffineTransform) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 50, y: 122), transform: t)
        p.addCurve(to: CGPoint(x: 50, y: 143), control1: CGPoint(x: 55, y: 129), control2: CGPoint(x: 54, y: 137), transform: t)
        p.addCurve(to: CGPoint(x: 50, y: 122), control1: CGPoint(x: 46, y: 137), control2: CGPoint(x: 45, y: 129), transform: t)
        p.closeSubpath()
        return p
    }

    /// Maps the viewBox into a y-**up** context: `height` tall, centred on
    /// `centre`. The y flip lives here and nowhere else.
    static func transform(centre: CGPoint, height: CGFloat) -> CGAffineTransform {
        let scale = height / viewBox.height
        return CGAffineTransform(translationX: centre.x - viewBox.width / 2 * scale,
                                 y: centre.y + viewBox.height / 2 * scale)
            .scaledBy(x: scale, y: -scale)
    }
}

// MARK: - Drawing

func drawIcon(in ctx: CGContext, pixels: Int) {
    let detail = Detail(pixels: pixels)
    let scale = CGFloat(pixels) / Sky.canvas

    ctx.saveGState()
    defer { ctx.restoreGState() }
    ctx.scaleBy(x: scale, y: scale)
    ctx.setShouldAntialias(true)

    let plate = RoundedRectangle(cornerRadius: Sky.cornerRadius, style: .continuous)
        .path(in: Sky.plate)
        .cgPath

    // The shadow comes from filling the plate opaquely; the gradient is painted
    // over it afterwards, clipped to the same shape.
    ctx.saveGState()
    ctx.setShadow(
        offset: Sky.shadowOffset,
        blur: Sky.shadowBlur,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: Sky.shadowAlpha)
    )
    ctx.addPath(plate)
    ctx.setFillColor(Sky.skyBottom)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(plate)
    ctx.clip()

    if let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [Sky.skyTop, Sky.skyBottom] as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: Sky.plate.midX, y: Sky.plate.maxY),
            end: CGPoint(x: Sky.plate.midX, y: Sky.plate.minY),
            options: []
        )
    }

    if detail.showsStars {
        for star in Sky.stars {
            let radius = star.r * Sky.plate.width
            let centre = CGPoint(
                x: Sky.plate.minX + star.x * Sky.plate.width,
                y: Sky.plate.maxY - star.y * Sky.plate.height
            )
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: star.alpha))
            ctx.fillEllipse(in: CGRect(
                x: centre.x - radius,
                y: centre.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
    }

    let transform = Rocket.transform(
        centre: CGPoint(x: Sky.plate.midX, y: Sky.plate.midY),
        height: detail.rocketHeightFraction * Sky.plate.height
    )

    if detail.showsFlame {
        ctx.addPath(Rocket.flame(transform))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85))
        ctx.fillPath()
    }

    // Hull, fins and nozzle are all white, so they are simply painted over each
    // other — no winding rules to get wrong where a fin meets the body.
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    for part in [Rocket.hull, Rocket.leftFin, Rocket.rightFin, Rocket.nozzle] {
        ctx.addPath(part(transform))
        ctx.fillPath()
    }

    if detail.showsPorthole {
        ctx.addPath(Rocket.window(transform))
        ctx.setFillColor(Sky.porthole)
        ctx.fillPath()
    }

    ctx.restoreGState()
}

func render(pixels: Int) -> CGImage? {
    guard let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .high
    drawIcon(in: ctx, pixels: pixels)
    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

// MARK: - Main

/// `iconutil` insists on all ten names, even though half of them are the same
/// pixel count as the next size up's 1×.
let members: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/make-appicon.swift <out.iconset>\n".utf8))
    exit(2)
}

let output = URL(fileURLWithPath: arguments[1])
do {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
} catch {
    FileHandle.standardError.write(Data("!! cannot create \(output.path): \(error.localizedDescription)\n".utf8))
    exit(1)
}

// One render per distinct pixel size, reused by both names that need it.
var rendered: [Int: CGImage] = [:]
for member in members {
    let image: CGImage
    if let cached = rendered[member.pixels] {
        image = cached
    } else {
        guard let fresh = render(pixels: member.pixels) else {
            FileHandle.standardError.write(Data("!! cannot render \(member.pixels) px\n".utf8))
            exit(1)
        }
        rendered[member.pixels] = fresh
        image = fresh
    }

    let url = output.appendingPathComponent(member.name)
    guard writePNG(image, to: url) else {
        FileHandle.standardError.write(Data("!! cannot write \(url.path)\n".utf8))
        exit(1)
    }
    print("    \(member.name) — \(member.pixels) px, detail: \(Detail(pixels: member.pixels))")
}

print("==> \(members.count) images in \(output.path)")
