#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Fixed pixel dimensions, independent of the screen's Retina scale.
let size = 1024
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/make-icon.swift output.png\n", stderr)
    exit(1)
}
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create icon bitmap")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let context = graphics.cgContext
context.clear(CGRect(x: 0, y: 0, width: size, height: size))
context.setAllowsAntialiasing(true)

let background = NSBezierPath(
    roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880),
    xRadius: 196, yRadius: 196
)

// Subtle drop shadow and a warm, upper-left light source.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedRed: 0.35, green: 0.12, blue: 0.02, alpha: 0.24)
shadow.shadowBlurRadius = 26
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor.orange.setFill()
background.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colors: [
    NSColor(calibratedRed: 1.00, green: 0.79, blue: 0.30, alpha: 1),
    NSColor(calibratedRed: 1.00, green: 0.49, blue: 0.13, alpha: 1),
    NSColor(calibratedRed: 0.91, green: 0.26, blue: 0.12, alpha: 1)
])!.draw(in: background, angle: -55)

// Broad rays stay recognizable at small Finder icon sizes.
let cream = NSColor(calibratedRed: 1, green: 0.97, blue: 0.84, alpha: 1)
context.setStrokeColor(cream.cgColor)
context.setLineWidth(42)
context.setLineCap(.round)
for ray in 0..<8 {
    let angle = CGFloat(ray) * .pi / 4
    context.move(to: CGPoint(x: 512 + cos(angle) * 226, y: 512 + sin(angle) * 226))
    context.addLine(to: CGPoint(x: 512 + cos(angle) * 294, y: 512 + sin(angle) * 294))
    context.strokePath()
}
let sun = NSBezierPath(ovalIn: NSRect(x: 354, y: 354, width: 316, height: 316))
NSGradient(starting: .white, ending: cream)!.draw(in: sun, angle: -90)
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
