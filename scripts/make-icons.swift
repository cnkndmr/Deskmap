#!/usr/bin/env swift
//
// Renders the Deskmap icons from code:
//
//   swift scripts/make-icons.swift
//
// Writes app/Resources/AppIcon.icns, AppIcon-1024.png, the AppIcon.appiconset
// PNGs and the MenuBarIcon template PNGs. The shapes mirror the design sources
// app/Resources/AppIcon.svg and MenuBarIcon.svg — change both together.
//
// Drawing in code rather than rasterising the SVG keeps the small sizes
// honest: below 64 px the title bar and its dots are dropped, because at that
// size they are three grey pixels and a smudge.

import AppKit

// MARK: - Paths

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let resources = root.appendingPathComponent("app/Resources")
let appIconSet = resources.appendingPathComponent("AppIcon.appiconset")

// MARK: - Colours

func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
    var value: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
    return CGColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: alpha)
}

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func gradient(_ from: String, _ to: String) -> CGGradient {
    CGGradient(colorsSpace: srgb,
               colors: [color(from), color(to)] as CFArray,
               locations: [0, 1])!
}

// MARK: - Rendering

/// Renders `draw` into a bitmap of `pixels` × `pixels` with a top-left origin,
/// the way the SVG sources are written.
func renderPNG(pixels: Int, points: NSSize, draw: (CGContext) -> Void) -> Data {
    guard let ctx = CGContext(
        data: nil, width: pixels, height: pixels == 0 ? 0 : pixels,
        bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("Could not create a \(pixels)px context") }
    ctx.interpolationQuality = .high
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: 1, y: -1)
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = points
    return rep.representation(using: .png, properties: [:])!
}

/// Same, for the non-square menu bar glyph.
func renderPNG(width: Int, height: Int, points: NSSize, draw: (CGContext) -> Void) -> Data {
    guard let ctx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("Could not create a \(width)×\(height) context") }
    ctx.interpolationQuality = .high
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = points
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - The marker

/// The map marker, in the 1024 unit box of AppIcon.svg.
func markerPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 512, y: 148))
    p.addCurve(to: CGPoint(x: 786, y: 418),
               control1: CGPoint(x: 663, y: 148), control2: CGPoint(x: 786, y: 268))
    p.addCurve(to: CGPoint(x: 512, y: 848),
               control1: CGPoint(x: 786, y: 566), control2: CGPoint(x: 616, y: 690))
    p.addCurve(to: CGPoint(x: 238, y: 418),
               control1: CGPoint(x: 408, y: 690), control2: CGPoint(x: 238, y: 566))
    p.addCurve(to: CGPoint(x: 512, y: 148),
               control1: CGPoint(x: 238, y: 268), control2: CGPoint(x: 361, y: 148))
    p.closeSubpath()
    return p
}

/// The app icon. `detailed` draws the window's title bar and its three dots;
/// at 32 px and below they are noise, so the small sizes drop them.
func drawAppIcon(_ ctx: CGContext, pixels: CGFloat, detailed: Bool) {
    ctx.scaleBy(x: pixels / 1024, y: pixels / 1024)

    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024),
                       cornerWidth: 230, cornerHeight: 230, transform: nil))
    ctx.clip()
    ctx.drawLinearGradient(gradient("#1D2A3A", "#0A0E14"),
                           start: CGPoint(x: 0, y: 0), end: CGPoint(x: 205, y: 1024),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    if detailed {
        ctx.setFillColor(color("#FFFFFF", alpha: 0.12))
        ctx.fillEllipse(in: CGRect(x: 362, y: 818, width: 300, height: 68))
    }

    ctx.saveGState()
    ctx.addPath(markerPath())
    ctx.clip()
    ctx.drawLinearGradient(gradient("#FFD37A", "#EE7B24"),
                           start: CGPoint(x: 0, y: 148), end: CGPoint(x: 0, y: 848),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // The head is a window.
    let window = CGRect(x: 342, y: 288, width: 340, height: 238)
    ctx.setFillColor(color("#14181D"))
    ctx.addPath(CGPath(roundedRect: window, cornerWidth: 34, cornerHeight: 34, transform: nil))
    ctx.fillPath()

    if detailed {
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: window, cornerWidth: 34, cornerHeight: 34, transform: nil))
        ctx.clip()
        ctx.setFillColor(color("#2B333C"))
        ctx.fill(CGRect(x: 342, y: 288, width: 340, height: 66))
        ctx.restoreGState()

        for (x, hex) in [(386.0, "#FF6157"), (428.0, "#FFC12F"), (470.0, "#2ACB42")] {
            ctx.setFillColor(color(hex))
            ctx.fillEllipse(in: CGRect(x: x - 13, y: 308, width: 26, height: 26))
        }
    }

    ctx.setFillColor(color("#FFFFFF", alpha: 0.92))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 382, y: detailed ? 394 : 366,
                                           width: 150, height: detailed ? 92 : 110),
                       cornerWidth: 16, cornerHeight: 16, transform: nil))
    ctx.fillPath()
}

/// The menu bar template: one solid shape, the window cut out of it. macOS
/// tints template images, so this is black plus alpha and nothing else.
func drawMenuBarIcon(_ ctx: CGContext, scale: CGFloat) {
    ctx.scaleBy(x: scale, y: scale)

    let p = CGMutablePath()
    p.move(to: CGPoint(x: 11, y: 0.8))
    p.addCurve(to: CGPoint(x: 17.5, y: 7.1),
               control1: CGPoint(x: 14.6, y: 0.8), control2: CGPoint(x: 17.5, y: 3.6))
    p.addCurve(to: CGPoint(x: 11, y: 15.6),
               control1: CGPoint(x: 17.5, y: 10.6), control2: CGPoint(x: 13.4, y: 12.9))
    p.addCurve(to: CGPoint(x: 4.5, y: 7.1),
               control1: CGPoint(x: 8.6, y: 12.9), control2: CGPoint(x: 4.5, y: 10.6))
    p.addCurve(to: CGPoint(x: 11, y: 0.8),
               control1: CGPoint(x: 4.5, y: 3.6), control2: CGPoint(x: 7.4, y: 0.8))
    p.closeSubpath()
    p.addRect(CGRect(x: 8.1, y: 4.1, width: 5.8, height: 1.2))   // title bar
    p.addRect(CGRect(x: 8.1, y: 6.1, width: 5.8, height: 3.2))   // window body

    ctx.setFillColor(color("#000000"))
    ctx.addPath(p)
    ctx.fillPath(using: .evenOdd)
}

// MARK: - Output

func write(_ data: Data, to url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try! data.write(to: url, options: .atomic)
    print("  ✓ \(url.path.replacingOccurrences(of: root.path + "/", with: ""))")
}

func appIcon(_ pixels: Int) -> Data {
    renderPNG(pixels: pixels, points: NSSize(width: pixels, height: pixels)) { ctx in
        drawAppIcon(ctx, pixels: CGFloat(pixels), detailed: pixels >= 64)
    }
}

print("==> App icon")
write(appIcon(1024), to: resources.appendingPathComponent("AppIcon-1024.png"))

// The names Xcode's asset catalogue expects, which this repo keeps by hand.
let catalogue: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
var rendered: [Int: Data] = [:]
for (name, pixels) in catalogue {
    let data = rendered[pixels] ?? appIcon(pixels)
    rendered[pixels] = data
    write(data, to: appIconSet.appendingPathComponent("\(name).png"))
}

print("==> AppIcon.icns")
let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("Deskmap-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, pixels) in catalogue {
    try! rendered[pixels]!.write(to: iconset.appendingPathComponent("\(name).png"))
}
let icns = Process()
icns.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
icns.arguments = ["-c", "icns", iconset.path,
                  "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! icns.run()
icns.waitUntilExit()
guard icns.terminationStatus == 0 else { fatalError("iconutil failed") }
try? FileManager.default.removeItem(at: iconset)
print("  ✓ app/Resources/AppIcon.icns")

print("==> Menu bar template")
write(renderPNG(width: 22, height: 16, points: NSSize(width: 22, height: 16)) { ctx in
    drawMenuBarIcon(ctx, scale: 1)
}, to: resources.appendingPathComponent("MenuBarIcon.png"))
write(renderPNG(width: 44, height: 32, points: NSSize(width: 22, height: 16)) { ctx in
    drawMenuBarIcon(ctx, scale: 2)
}, to: resources.appendingPathComponent("MenuBarIcon@2x.png"))

print("\nDone. Rebuild the app to see them: make app")
