#!/usr/bin/env swift
/// Generates MacBlinker.icns from scratch using AppKit drawing.
/// Run:  swift create_icon.swift
import AppKit

// MARK: - Drawing

func makeIconImage(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let ctx = NSGraphicsContext.current!.cgContext

        // ── Background: dark rounded square ──────────────────────
        let radius = size * 0.22
        let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(bgPath)
        ctx.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1))
        ctx.fillPath()

        // ── Outer soft glow ───────────────────────────────────────
        let glowInset = size * 0.10
        let glowRect  = rect.insetBy(dx: glowInset, dy: glowInset)
        ctx.saveGState()
        ctx.addPath(bgPath)
        ctx.clip()
        ctx.setShadow(offset: .zero, blur: size * 0.18,
                      color: CGColor(red: 0.18, green: 0.85, blue: 0.35, alpha: 0.55))
        ctx.setFillColor(CGColor(red: 0.18, green: 0.85, blue: 0.35, alpha: 0.20))
        ctx.fillEllipse(in: glowRect)
        ctx.restoreGState()

        // ── Main circle ───────────────────────────────────────────
        let circInset = size * 0.22
        let circRect  = rect.insetBy(dx: circInset, dy: circInset)
        // Gradient fill: bright lime-green at top, deep green at bottom
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(red: 0.45, green: 1.00, blue: 0.45, alpha: 1),  // top highlight
                CGColor(red: 0.10, green: 0.72, blue: 0.25, alpha: 1),  // bottom deep green
            ] as CFArray,
            locations: [0, 1]
        )!
        ctx.saveGState()
        ctx.addEllipse(in: circRect)
        ctx.clip()
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: circRect.midX, y: circRect.maxY),
            end:   CGPoint(x: circRect.midX, y: circRect.minY),
            options: []
        )
        ctx.restoreGState()

        // ── Inner specular highlight (top-left crescent) ──────────
        let hlInset = size * 0.28
        let hlRect  = CGRect(
            x: circRect.minX + (circRect.width * 0.08),
            y: circRect.midY + (circRect.height * 0.08),
            width:  circRect.width  * 0.55,
            height: circRect.height * 0.38
        )
        ctx.saveGState()
        ctx.addEllipse(in: circRect)  // clip to circle boundary
        ctx.clip()
        ctx.setFillColor(CGColor(red: 0.85, green: 1, blue: 0.85, alpha: 0.35))
        ctx.fillEllipse(in: hlRect)
        ctx.restoreGState()

        // ── Thin ring border ──────────────────────────────────────
        ctx.addEllipse(in: circRect.insetBy(dx: 0.5, dy: 0.5))
        ctx.setStrokeColor(CGColor(red: 1, green: 0.5, blue: 0.5, alpha: 0.25))
        ctx.setLineWidth(max(1, size * 0.012))
        ctx.strokePath()

        return true
    }
    img.isTemplate = false
    return img
}

// MARK: - PNG export helper

func pngData(from image: NSImage, at size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: rep.size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Main

// iconset entries: (filename, render size in px)
let entries: [(String, CGFloat)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png",1024),
]

let fm = FileManager.default
let iconsetDir = URL(fileURLWithPath: "MacBlinker.iconset")
try? fm.removeItem(at: iconsetDir)
try! fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

for (filename, size) in entries {
    let image = makeIconImage(size: size)
    let data  = pngData(from: image, at: size)
    let dest  = iconsetDir.appendingPathComponent(filename)
    try! data.write(to: dest)
    print("✓ \(filename)  (\(Int(size))px)")
}

print("\nRunning iconutil…")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", "-o", "Resources/AppIcon.icns", "MacBlinker.iconset"]
try! task.run()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("✓ Resources/AppIcon.icns created")
    try? fm.removeItem(at: iconsetDir)   // clean up temp iconset folder
    print("✓ Cleaned up MacBlinker.iconset")
} else {
    print("✗ iconutil failed — check MacBlinker.iconset manually")
}
