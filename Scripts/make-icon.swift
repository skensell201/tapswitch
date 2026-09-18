#!/usr/bin/env swift
// Draws Resources/AppIcon.icns from scratch.
//
// The icon is generated rather than checked in as a binary blob nobody can
// edit: the shape is a few numbers, and this way a tweak is a diff. Run it
// after changing anything here, then commit the regenerated .icns alongside.
//
// Every size is drawn at its own resolution rather than downsampled from one
// master, so the small ones stay crisp.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The system's squircle mask clips the corners of a full-bleed icon; the
/// glyph stays inside this fraction of the canvas so nothing important is lost.
let safeArea: CGFloat = 0.86

let backgroundTop = CGColor(red: 0.23, green: 0.23, blue: 0.25, alpha: 1)
let backgroundBottom = CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
/// The two layouts the tap switches between.
let layoutA = CGColor(red: 0.04, green: 0.52, blue: 1.00, alpha: 1)
let layoutB = CGColor(red: 1.00, green: 0.62, blue: 0.04, alpha: 1)

func draw(size: CGFloat) -> CGImage {
    let pixels = Int(size)
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setAllowsAntialiasing(true)

    // Full-bleed on purpose: macOS 26 masks an app icon into its own squircle
    // and casts its own shadow. Drawing a plate here too would put a second,
    // smaller tile inside the system's one.
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [backgroundTop, backgroundBottom] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 0, y: size), end: .zero, options: [])

    let safe = size * safeArea
    let glyphWidth = safe * 0.80
    let left = (size - glyphWidth) / 2

    // The glyph, top to bottom: five fingertips in an arc — the tap — above a
    // pill split between two colours — the layouts being swapped.
    let dotRadius = glyphWidth * 0.088
    let arcDrop = glyphWidth * 0.135
    let barHeight = glyphWidth * 0.185
    let spacer = glyphWidth * 0.165
    let groupHeight = dotRadius * 2 + arcDrop + spacer + barHeight

    // Centre the group as a whole rather than pad from the top, so a change to
    // any one band cannot quietly push the glyph off-centre.
    let bottom = (size - groupHeight) / 2
    let barY = bottom
    let dotCentreY = bottom + barHeight + spacer + dotRadius

    let bar = CGRect(x: left, y: barY, width: glyphWidth, height: barHeight)
    context.saveGState()
    context.addPath(CGPath(
        roundedRect: bar, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2,
        transform: nil))
    context.clip()
    context.setFillColor(layoutA)
    context.fill(CGRect(x: bar.minX, y: bar.minY, width: bar.width / 2, height: bar.height))
    context.setFillColor(layoutB)
    context.fill(CGRect(x: bar.midX, y: bar.minY, width: bar.width / 2, height: bar.height))
    context.restoreGState()

    // Five dots on an arc: the middle finger highest, the outer two lowest.
    // `t` runs -1…1 across them, so the drop is a plain parabola.
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    let span = glyphWidth - dotRadius * 2
    for index in 0..<5 {
        let t = (CGFloat(index) - 2) / 2
        let x = left + dotRadius + span * CGFloat(index) / 4
        let y = dotCentreY - arcDrop * t * t
        context.fillEllipse(in: CGRect(
            x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
    }

    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
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
        write(
            draw(size: CGFloat(pixels)),
            to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}

let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
print(output.path)
