#!/usr/bin/env swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let work = root.appendingPathComponent("build/icon", isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

let size = CGFloat(1024)
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else { fatalError("No graphics context") }
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let iconRect = NSRect(x: 92, y: 92, width: 840, height: 840)
let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 190, yRadius: 190)

// A soft drop shadow gives the icon presence in the Dock without a baked
// background plate.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.36)
shadow.shadowBlurRadius = 44
shadow.shadowOffset = NSSize(width: 0, height: -16)
shadow.set()
NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 1).setFill()
iconPath.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
iconPath.addClip()
let background = NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.24, alpha: 1),
    NSColor(calibratedRed: 0.055, green: 0.06, blue: 0.085, alpha: 1)
])!
background.draw(in: iconRect, angle: -90)

// Faint architectural grid, like a quiet blueprint.
NSColor.white.withAlphaComponent(0.035).setStroke()
for x in stride(from: 170.0, through: 860.0, by: 86.0) {
    let line = NSBezierPath()
    line.move(to: NSPoint(x: x, y: 120))
    line.line(to: NSPoint(x: x, y: 905))
    line.lineWidth = 2
    line.stroke()
}
for y in stride(from: 150.0, through: 880.0, by: 86.0) {
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 110, y: y))
    line.line(to: NSPoint(x: 914, y: y))
    line.lineWidth = 2
    line.stroke()
}
NSGraphicsContext.restoreGraphicsState()

// The window: a warm arched bay, the "oriel" itself.
let arch = NSBezierPath()
arch.move(to: NSPoint(x: 318, y: 270))
arch.line(to: NSPoint(x: 318, y: 548))
arch.curve(to: NSPoint(x: 512, y: 770),
           controlPoint1: NSPoint(x: 318, y: 680),
           controlPoint2: NSPoint(x: 382, y: 770))
arch.curve(to: NSPoint(x: 706, y: 548),
           controlPoint1: NSPoint(x: 642, y: 770),
           controlPoint2: NSPoint(x: 706, y: 680))
arch.line(to: NSPoint(x: 706, y: 270))
arch.close()

NSGraphicsContext.saveGraphicsState()
let glow = NSShadow()
glow.shadowColor = NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.34, alpha: 0.26)
glow.shadowBlurRadius = 58
glow.shadowOffset = .zero
glow.set()
NSColor(calibratedRed: 0.92, green: 0.85, blue: 0.69, alpha: 1).setFill()
arch.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
arch.addClip()
let glass = NSGradient(colors: [
    NSColor(calibratedRed: 0.99, green: 0.95, blue: 0.84, alpha: 1),
    NSColor(calibratedRed: 0.79, green: 0.65, blue: 0.40, alpha: 1)
])!
glass.draw(in: arch.bounds, angle: -68)

// Three panes, each a slightly different time of day.
let paneRects = [
    NSRect(x: 345, y: 298, width: 150, height: 355),
    NSRect(x: 522, y: 298, width: 150, height: 355)
]
NSColor(calibratedRed: 0.30, green: 0.36, blue: 0.52, alpha: 1).setFill()
NSBezierPath(roundedRect: paneRects[0], xRadius: 4, yRadius: 4).fill()
NSColor(calibratedRed: 0.98, green: 0.79, blue: 0.48, alpha: 1).setFill()
NSBezierPath(roundedRect: paneRects[1], xRadius: 4, yRadius: 4).fill()

let transomY: CGFloat = 568
NSColor(calibratedRed: 0.30, green: 0.25, blue: 0.18, alpha: 0.9).setFill()
NSRect(x: 330, y: transomY, width: 364, height: 16).fill()
NSRect(x: 495, y: 285, width: 21, height: 475).fill()
NSRect(x: 330, y: 285, width: 364, height: 18).fill()

// A thin brass highlight along the arch.
let highlight = NSBezierPath()
highlight.move(to: NSPoint(x: 340, y: 548))
highlight.curve(to: NSPoint(x: 512, y: 748),
                controlPoint1: NSPoint(x: 340, y: 670),
                controlPoint2: NSPoint(x: 402, y: 748))
highlight.curve(to: NSPoint(x: 684, y: 548),
                controlPoint1: NSPoint(x: 622, y: 748),
                controlPoint2: NSPoint(x: 684, y: 670))
highlight.lineWidth = 7
NSColor(calibratedRed: 1, green: 0.90, blue: 0.70, alpha: 0.62).setStroke()
highlight.stroke()
NSGraphicsContext.restoreGraphicsState()

// Subtle inner rim.
NSGraphicsContext.saveGraphicsState()
iconPath.addClip()
let rim = NSBezierPath(roundedRect: iconRect.insetBy(dx: 3, dy: 3), xRadius: 187, yRadius: 187)
rim.lineWidth = 5
NSColor.white.withAlphaComponent(0.08).setStroke()
rim.stroke()
NSGraphicsContext.restoreGraphicsState()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else { fatalError("Could not render icon") }
let master = work.appendingPathComponent("AppIcon-1024.png")
try png.write(to: master)

let iconset = work.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, px) in sizes {
    let output = iconset.appendingPathComponent(name)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(px)", "\(px)", master.path, "--out", output.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
}

let icns = resources.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
print("✓ \(icns.path)")
