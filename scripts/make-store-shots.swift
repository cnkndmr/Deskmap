#!/usr/bin/env swift
//
// Builds store/landing-page screenshots from the raw interface captures:
//
//   swift scripts/make-store-shots.swift
//
// Reads docs/images/{en,tr}/*.png (produced by `Deskmap --shots`) and writes
// docs/store/{en,tr}/ at the two sizes App Store Connect accepts for macOS,
// 2880×1800 and 1280×800 — the raw captures are 1120×1280 and would be
// rejected outright.
//
// Each frame is the real interface on a backdrop with one line of copy. No
// mockup device frames, no invented UI: the window is the capture, unedited.

import AppKit

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

struct Frame {
    let file: String
    let en: String
    let tr: String
}

let frames = [
    Frame(file: "01-map",
          en: "Every display, every desktop, one screen",
          tr: "Bütün ekranlar, bütün masaüstleri, tek ekranda"),
    Frame(file: "02-pin",
          en: "Pin a window by what its title says",
          tr: "Pencereyi başlığının söylediğine göre pinle"),
    Frame(file: "03-layout",
          en: "Full, halves, 70/30 — applied once",
          tr: "Tam, yarım, %70/%30 — bir kez uygulanır"),
    Frame(file: "04-profiles",
          en: "Desk, café, presentation",
          tr: "Masa, kafe, sunum"),
    Frame(file: "05-setup",
          en: "It tells you exactly what to fix",
          tr: "Neyi düzeltmen gerektiğini tek tek söyler"),
]

let wordmark = "DESKMAP"

func color(_ hex: String, alpha: CGFloat = 1) -> NSColor {
    var value: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
    return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                   green: CGFloat((value >> 8) & 0xFF) / 255,
                   blue: CGFloat(value & 0xFF) / 255,
                   alpha: alpha)
}

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

/// Draws one frame at `width` × `height`, scaling every measurement from the
/// 2880-wide reference layout.
func draw(shot: CGImage, caption: String, width: Int, height: Int) -> Data {
    guard let ctx = CGContext(data: nil, width: width, height: height,
                              bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("Could not create a \(width)×\(height) context") }
    let s = CGFloat(width) / 2880

    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high

    // Backdrop: the icon's colours, so the frames and the app agree.
    let gradient = CGGradient(colorsSpace: srgb,
                              colors: [color("#1D2A3A").cgColor, color("#090D12").cgColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: 0),
                           end: CGPoint(x: CGFloat(width) * 0.25, y: CGFloat(height)),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // A soft amber wash behind the window, picked up from the marker.
    let wash = CGGradient(colorsSpace: srgb,
                          colors: [color("#F08A2E", alpha: 0.20).cgColor,
                                   color("#F08A2E", alpha: 0).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(wash,
                           startCenter: CGPoint(x: CGFloat(width) / 2, y: 980 * s), startRadius: 0,
                           endCenter: CGPoint(x: CGFloat(width) / 2, y: 980 * s), endRadius: 1500 * s,
                           options: [])

    let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ns

    let centred = NSMutableParagraphStyle()
    centred.alignment = .center

    NSAttributedString(string: wordmark, attributes: [
        .font: NSFont.systemFont(ofSize: 34 * s, weight: .semibold),
        .foregroundColor: color("#F0A254"),
        .kern: 10 * s,
        .paragraphStyle: centred,
    ]).draw(in: CGRect(x: 0, y: 150 * s, width: CGFloat(width), height: 60 * s))

    NSAttributedString(string: caption, attributes: [
        .font: NSFont.systemFont(ofSize: 96 * s, weight: .semibold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: centred,
    ]).draw(in: CGRect(x: 200 * s, y: 236 * s, width: CGFloat(width) - 400 * s, height: 220 * s))

    NSGraphicsContext.restoreGraphicsState()

    // The capture itself: rounded corners and a shadow, nothing else touched.
    let shotHeight = 1240 * s
    let shotWidth = shotHeight * CGFloat(shot.width) / CGFloat(shot.height)
    let rect = CGRect(x: (CGFloat(width) - shotWidth) / 2, y: 470 * s,
                      width: shotWidth, height: shotHeight)
    let rounded = CGPath(roundedRect: rect, cornerWidth: 28 * s, cornerHeight: 28 * s,
                         transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -30 * s), blur: 70 * s,
                  color: color("#000000", alpha: 0.55).cgColor)
    ctx.setFillColor(color("#0B0F14").cgColor)
    ctx.addPath(rounded)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(rounded)
    ctx.clip()
    // The context is flipped for text; flip back so the capture isn't mirrored.
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(shot, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
    ctx.restoreGState()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: width, height: height)
    return rep.representation(using: .png, properties: [:])!
}

func loadImage(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fatalError("Could not read \(url.path)") }
    return image
}

for language in ["en", "tr"] {
    let input = root.appendingPathComponent("docs/images/\(language)")
    let output = root.appendingPathComponent("docs/store/\(language)")
    try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    print("==> \(language)")

    for frame in frames {
        let shot = loadImage(input.appendingPathComponent("\(frame.file).png"))
        let caption = language == "tr" ? frame.tr : frame.en

        for (suffix, width, height) in [("-2880x1800", 2880, 1800), ("-1280x800", 1280, 800)] {
            let data = draw(shot: shot, caption: caption, width: width, height: height)
            let url = output.appendingPathComponent("\(frame.file)\(suffix).png")
            try! data.write(to: url, options: .atomic)
            print("  ✓ docs/store/\(language)/\(frame.file)\(suffix).png")
        }
    }
}

print("\nDone. These are the sizes App Store Connect accepts for macOS.")
