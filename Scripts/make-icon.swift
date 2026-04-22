#!/usr/bin/env swift
// Renders AppIcon.svg → AppIcon.icns via an intermediate iconset.
// Usage: swift Scripts/make-icon.swift <svg-path> <iconset-dir> <output.icns>

import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else {
    fputs("Usage: make-icon.swift <svg> <iconset-dir> <output.icns>\n", stderr)
    exit(1)
}

guard let source = NSImage(contentsOfFile: args[1]) else {
    fputs("Cannot load SVG: \(args[1])\n", stderr); exit(1)
}

let iconset = URL(fileURLWithPath: args[2])
let icnsOut  = args[3]

try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func renderPNG(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

for (name, px) in sizes {
    try! renderPNG(pixels: px).write(to: iconset.appendingPathComponent(name))
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", icnsOut]
try! p.run()
p.waitUntilExit()

guard p.terminationStatus == 0 else {
    fputs("iconutil failed\n", stderr); exit(1)
}
print("Icon: \(icnsOut)")
