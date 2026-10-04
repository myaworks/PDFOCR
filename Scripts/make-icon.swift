#!/usr/bin/env swift
// Draws AppIcon.icns.
//
//   Scripts/make-icon.swift
//
// Swift draws CoreGraphics better than anything else on the machine, and the
// result is committed as Resources/AppIcon.icns so that building the app never
// depends on regenerating it. Run this only when the icon itself changes.
//
// The shape follows what macOS expects: a rounded container inset from the
// canvas with the artwork inside it, so the icon sits correctly next to others
// in the Finder and the Dock.

import AppKit
import CoreGraphics
import Foundation

let size = 1024
let inset = 100.0
let side = Double(size) - inset * 2
let radius = side * 0.225

// macOS 26 draws app icons on a rounded container. Inset artwork, not the
// artwork itself, carries the meaning: a page with lines that some tool has
// turned back into text.
let canvas = CGRect(x: 0, y: 0, width: size, height: size)
let plate = CGRect(x: inset, y: inset, width: side, height: side)

let palette: [String: NSColor] = [
    "top": NSColor(srgbRed: 0.36, green: 0.58, blue: 1.00, alpha: 1),
    "bottom": NSColor(srgbRed: 0.07, green: 0.20, blue: 0.58, alpha: 1),
    "page": NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
    "line": NSColor(srgbRed: 0.74, green: 0.79, blue: 0.86, alpha: 1),
    "found": NSColor(srgbRed: 0.04, green: 0.47, blue: 0.98, alpha: 1),
    "foundSoft": NSColor(srgbRed: 0.35, green: 0.72, blue: 1.00, alpha: 1),
]

func cg(_ name: String, alpha: CGFloat? = nil) -> CGColor {
    let c = palette[name]!
    return c.withAlphaComponent(alpha ?? c.alphaComponent).cgColor
}

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    FileHandle.standardError.write(Data("no graphics context\n".utf8))
    exit(1)
}

// The context is y-up; flip so the drawing reads top-down like a page.
ctx.translateBy(x: 0, y: Double(size))
ctx.scaleBy(x: 1, y: -1)
ctx.setAllowsAntialiasing(true)
ctx.interpolationQuality = .high

// MARK: - plate

let platePath = CGPath(
    roundedRect: plate,
    cornerWidth: radius,
    cornerHeight: radius,
    transform: nil
)

ctx.saveGState()
ctx.addPath(platePath)
ctx.clip()
let plateGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [cg("top"), cg("bottom")] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    plateGradient,
    start: CGPoint(x: plate.minX, y: plate.minY),
    end: CGPoint(x: plate.maxX, y: plate.maxY),
    options: []
)
ctx.restoreGState()

// a light along the top edge, the way the system renders these
ctx.saveGState()
ctx.addPath(platePath)
ctx.clip()
let sheen = CGRect(x: plate.minX, y: plate.minY, width: plate.width, height: plate.height * 0.5)
let sheenGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor.white.withAlphaComponent(0.28).cgColor,
        NSColor.white.withAlphaComponent(0.0).cgColor,
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    sheenGradient,
    start: CGPoint(x: sheen.midX, y: sheen.minY),
    end: CGPoint(x: sheen.midX, y: sheen.maxY),
    options: []
)
ctx.restoreGState()

// MARK: - the page

// Big enough to still read at 16 px, where a busier page turns to mush.
let pageWidth = side * 0.60
let pageHeight = side * 0.70
let page = CGRect(
    x: plate.midX - pageWidth / 2,
    y: plate.midY - pageHeight / 2 + side * 0.015,
    width: pageWidth,
    height: pageHeight
)
let pagePath = CGPath(
    roundedRect: page,
    cornerWidth: pageWidth * 0.075,
    cornerHeight: pageWidth * 0.075,
    transform: nil
)

ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -side * 0.012),
    blur: side * 0.05,
    color: NSColor.black.withAlphaComponent(0.28).cgColor
)
ctx.addPath(pagePath)
ctx.setFillColor(cg("page"))
ctx.fillPath()
ctx.restoreGState()

// MARK: - lines of text

// Upper lines are the scan: flat grey. The lower ones are what OCR gave back,
// picked out in blue. At 16 px the two colours still read as different weights.
let barHeight = pageHeight * 0.058
let barRadius = barHeight / 2
let left = page.minX + pageWidth * 0.14
let right = page.maxX - pageWidth * 0.14
let usable = right - left

struct Row {
    let width: CGFloat
    let recovered: Bool
}

// Five lines: three still just a picture of text, two given back as text.
// Alternating them reads as "some of this is searchable now" at any size.
let rows: [Row] = [
    Row(width: 1.00, recovered: false),
    Row(width: 0.88, recovered: true),
    Row(width: 0.96, recovered: false),
    Row(width: 0.84, recovered: true),
    Row(width: 0.92, recovered: false),
]

let gap = pageHeight * 0.052
let blockHeight = CGFloat(rows.count) * barHeight + CGFloat(rows.count - 1) * gap
var y = page.midY + blockHeight / 2 - barHeight

for row in rows {
    let rect = CGRect(x: left, y: y, width: usable * row.width, height: barHeight)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: barRadius, cornerHeight: barRadius, transform: nil))
    ctx.setFillColor(cg(row.recovered ? "found" : "line"))
    ctx.fillPath()
    y -= barHeight + gap
}

image.unlockFocus()

// MARK: - write the iconset

// MARK: sizes

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("no bitmap rep\n".utf8))
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("no png\n".utf8))
    exit(1)
}

let root = URL(fileURLWithPath: "Resources")
let iconset = root.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

for (points, name) in variants {
    let target = CGFloat(points)
    let small = NSImage(size: NSSize(width: target, height: target))
    small.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: target, height: target),
        from: NSRect(x: 0, y: 0, width: size, height: size),
        operation: .copy,
        fraction: 1
    )
    small.unlockFocus()

    guard let smallRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(target),
        pixelsHigh: Int(target),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: smallRep)
    small.draw(in: NSRect(x: 0, y: 0, width: target, height: target))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = smallRep.representation(using: .png, properties: [:]) else { continue }
    try data.write(to: iconset.appendingPathComponent(name))
}

print("wrote \(iconset.path)")

let tool = Process()
tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
tool.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("AppIcon.icns").path]
try tool.run()
tool.waitUntilExit()

if tool.terminationStatus != 0 {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}
print("wrote \(root.appendingPathComponent("AppIcon.icns").path)")