#!/usr/bin/env swift
// Draws every picture of the TapSwitch mark from scratch:
//
//   Resources/AppIcon.icns      — the app icon, in colour on a dark tile
//   Resources/StatusIcon.pdf    — the menu bar template, vector, black on clear
//   docs/logo.png               — the README logo
//
// The pictures are generated rather than checked in as binary blobs nobody can
// edit: the shape is a few numbers, and this way a tweak is a diff. Run it
// after changing anything here, then commit the regenerated files alongside.
//
// Every icon size is drawn at its own resolution rather than downsampled from
// one master, so the small ones stay crisp.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - The mark

/// The mark, in units of its own radius: a fingertip — the tap — inside two
/// arrows chasing each other round — the two layouts being swapped.
struct Mark {
    var ringRadius: CGFloat = 0.74
    var ringWidth: CGFloat = 0.20
    var dotRadius: CGFloat = 0.27
    /// Half the angle left empty between the two arrows, at each side.
    var gap: CGFloat = 26
    var arrowLength: CGFloat = 0.34
    var arrowHalfWidth: CGFloat = 0.25

    /// Fills the mark centred on `centre`, `radius` points from centre to the
    /// arrowheads' outer corners. Colours are top arrow, bottom arrow, dot.
    func draw(
        in context: CGContext, centre: CGPoint, radius: CGFloat,
        top: CGColor, bottom: CGColor, dot: CGColor
    ) {
        context.saveGState()
        context.translateBy(x: centre.x, y: centre.y)
        context.scaleBy(x: radius, y: radius)

        // Both arrows run clockwise: the top one left to right, the bottom one
        // right to left. Each starts just past one gap and stops short of the
        // next, leaving room for its head.
        arrow(in: context, from: 180 - gap, to: gap, colour: top)
        arrow(in: context, from: -gap, to: -180 + gap, colour: bottom)

        context.setFillColor(dot)
        context.fillEllipse(in: CGRect(
            x: -dotRadius, y: -dotRadius, width: dotRadius * 2, height: dotRadius * 2))
        context.restoreGState()
    }

    /// A clockwise arc from `start` to `end` degrees, with a head at `end`.
    private func arrow(in context: CGContext, from start: CGFloat, to end: CGFloat, colour: CGColor) {
        // The head's length is measured along the ring, so the shaft stops
        // where the head's base begins.
        let headSweep = arrowLength / ringRadius * 180 / .pi
        let shaftEnd = end + headSweep

        context.setFillColor(colour)
        context.setStrokeColor(colour)
        context.setLineWidth(ringWidth)
        context.setLineCap(.round)
        context.addArc(
            center: .zero, radius: ringRadius,
            startAngle: radians(start), endAngle: radians(shaftEnd), clockwise: true)
        context.strokePath()

        let base = radians(shaftEnd)
        let tipAngle = radians(end)
        let inner = point(angle: base, radius: ringRadius - arrowHalfWidth)
        let outer = point(angle: base, radius: ringRadius + arrowHalfWidth)
        let tip = point(angle: tipAngle, radius: ringRadius)
        context.move(to: inner)
        context.addLine(to: outer)
        context.addLine(to: tip)
        context.closePath()
        context.fillPath()
    }

    private func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

    private func point(angle: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
    }
}

// MARK: - Colours

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let backgroundTop = CGColor(red: 0.23, green: 0.23, blue: 0.25, alpha: 1)
let backgroundBottom = CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
/// The two layouts the tap switches between: violet and teal. Never blue over
/// yellow — together they read as a national flag.
let layoutA = CGColor(red: 0.55, green: 0.42, blue: 1.00, alpha: 1)
let layoutB = CGColor(red: 0.13, green: 0.83, blue: 0.75, alpha: 1)
let white = CGColor(gray: 1, alpha: 1)
let black = CGColor(gray: 0, alpha: 1)

// MARK: - App icon

/// The system's squircle mask clips the corners of a full-bleed icon; the
/// mark stays inside this fraction of the canvas so nothing important is lost.
let safeArea: CGFloat = 0.86

func bitmap(size: Int) -> CGContext {
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setAllowsAntialiasing(true)
    return context
}

func appIcon(size: CGFloat) -> CGImage {
    let context = bitmap(size: Int(size))

    // Full-bleed on purpose: macOS 26 masks an app icon into its own squircle
    // and casts its own shadow. Drawing a plate here too would put a second,
    // smaller tile inside the system's one.
    let gradient = CGGradient(
        colorsSpace: sRGB, colors: [backgroundTop, backgroundBottom] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 0, y: size), end: .zero, options: [])

    Mark().draw(
        in: context, centre: CGPoint(x: size / 2, y: size / 2),
        radius: size * safeArea * 0.40, top: layoutA, bottom: layoutB, dot: white)
    return context.makeImage()!
}

// MARK: - Menu bar

/// The menu bar draws a template image in its own colour, so only the alpha
/// matters. 18 points is the height of a standard status item's glyph.
let statusPoints: CGFloat = 18

/// At menu bar size the hairlines of the full mark would blur into the dot, so
/// the template gets a heavier cut of the same shape.
let statusMark = Mark(
    ringRadius: 0.72, ringWidth: 0.21, dotRadius: 0.25, gap: 30,
    arrowLength: 0.36, arrowHalfWidth: 0.27)

func writeStatusIcon(to url: URL) {
    var box = CGRect(x: 0, y: 0, width: statusPoints, height: statusPoints)
    let context = CGContext(url as CFURL, mediaBox: &box, nil)!
    context.beginPDFPage(nil)
    statusMark.draw(
        in: context, centre: CGPoint(x: box.midX, y: box.midY), radius: statusPoints / 2,
        top: black, bottom: black, dot: black)
    context.endPDFPage()
    context.closePDF()
}

// MARK: - README logo

/// The mark on its own, no tile, so it sits on either GitHub theme.
func logo(size: CGFloat) -> CGImage {
    let context = bitmap(size: Int(size))
    Mark().draw(
        in: context, centre: CGPoint(x: size / 2, y: size / 2), radius: size / 2,
        top: layoutA, bottom: layoutB, dot: CGColor(gray: 0.45, alpha: 1))
    return context.makeImage()!
}

// MARK: - Output

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("could not write \(url.path)")
    }
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let staging = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("AppIcon-\(UUID().uuidString)")
let iconset = staging.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: staging) }

for points in [16, 32, 128, 256, 512] {
    for (factor, suffix) in [(1, ""), (2, "@2x")] {
        let pixels = points * factor
        writePNG(
            appIcon(size: CGFloat(pixels)),
            to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}

let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
print(icns.path)

let status = root.appendingPathComponent("Resources/StatusIcon.pdf")
writeStatusIcon(to: status)
print(status.path)

let logoURL = root.appendingPathComponent("docs/logo.png")
try FileManager.default.createDirectory(
    at: logoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
writePNG(logo(size: 512), to: logoURL)
print(logoURL.path)
