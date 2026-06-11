#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate_app_icons.swift <output-directory>\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconsetURL = outputURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let iosURL = outputURL.appendingPathComponent("ios", isDirectory: true)

try? FileManager.default.removeItem(at: outputURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iosURL, withIntermediateDirectories: true)

let macIcons: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1_024)
]

let iosIcons: [(name: String, size: Int)] = [
    ("AppIcon-76.png", 76),
    ("AppIcon-76@2x.png", 152),
    ("AppIcon-83.5@2x.png", 167),
    ("AppIcon-1024.png", 1_024)
]

for icon in macIcons {
    try drawVaDaIcon(size: icon.size, to: iconsetURL.appendingPathComponent(icon.name))
}

for icon in iosIcons {
    try drawVaDaIcon(size: icon.size, to: iosURL.appendingPathComponent(icon.name))
}

private func drawVaDaIcon(size: Int, to url: URL) throws {
    guard let representation = NSBitmapImageRep(
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
        throw IconError.renderFailed
    }

    representation.size = NSSize(width: size, height: size)

    guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
        throw IconError.renderFailed
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let canvas = NSRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
    NSColor.clear.setFill()
    NSBezierPath(rect: canvas).fill()

    drawMark(in: canvas)

    NSGraphicsContext.restoreGraphicsState()

    guard let data = representation.representation(using: .png, properties: [.compressionFactor: 0.9]) else {
        throw IconError.renderFailed
    }

    try data.write(to: url, options: .atomic)
}

private func drawMark(in canvas: NSRect) {
    let size = min(canvas.width, canvas.height)
    let inset = size * 0.045
    let rect = canvas.insetBy(dx: inset, dy: inset)
    let cornerRadius = size * 0.22

    let background = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.045, green: 0.39, blue: 0.31, alpha: 1),
        NSColor(srgbRed: 0.08, green: 0.58, blue: 0.44, alpha: 1)
    ])
    gradient?.draw(in: background, angle: 315)

    NSColor.white.withAlphaComponent(0.18).setStroke()
    background.lineWidth = max(1, size * 0.012)
    background.stroke()

    let sunColor = NSColor(srgbRed: 1.0, green: 0.78, blue: 0.24, alpha: 1)
    drawSun(in: rect, color: sunColor)
    drawHouse(in: rect)
}

private func drawSun(in rect: NSRect, color: NSColor) {
    let size = min(rect.width, rect.height)
    let center = CGPoint(x: rect.minX + rect.width * 0.68, y: rect.minY + rect.height * 0.70)
    let radius = size * 0.095
    let innerRay = radius * 1.45
    let outerRay = radius * 2.05

    let rays = NSBezierPath()
    rays.lineCapStyle = .round
    rays.lineWidth = max(1.2, size * 0.035)

    for index in 0..<8 {
        let angle = Double(index) * Double.pi / 4.0
        let innerPoint = CGPoint(
            x: center.x + CGFloat(cos(angle)) * innerRay,
            y: center.y + CGFloat(sin(angle)) * innerRay
        )
        let outerPoint = CGPoint(
            x: center.x + CGFloat(cos(angle)) * outerRay,
            y: center.y + CGFloat(sin(angle)) * outerRay
        )
        rays.move(to: innerPoint)
        rays.line(to: outerPoint)
    }

    color.setStroke()
    rays.stroke()

    color.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )).fill()
}

private func drawHouse(in rect: NSRect) {
    let size = min(rect.width, rect.height)
    let p: (CGFloat, CGFloat) -> CGPoint = { x, y in
        CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }

    NSColor.white.withAlphaComponent(0.96).setFill()

    let chimney = NSBezierPath(roundedRect: NSRect(
        x: rect.minX + rect.width * 0.63,
        y: rect.minY + rect.height * 0.45,
        width: rect.width * 0.075,
        height: rect.height * 0.15
    ), xRadius: size * 0.012, yRadius: size * 0.012)
    chimney.fill()

    let house = NSBezierPath()
    house.move(to: p(0.22, 0.39))
    house.line(to: p(0.50, 0.63))
    house.line(to: p(0.78, 0.39))
    house.line(to: p(0.70, 0.39))
    house.line(to: p(0.70, 0.24))
    house.line(to: p(0.30, 0.24))
    house.line(to: p(0.30, 0.39))
    house.close()
    house.fill()

    NSColor(srgbRed: 0.045, green: 0.39, blue: 0.31, alpha: 0.85).setFill()
    let door = NSBezierPath(roundedRect: NSRect(
        x: rect.minX + rect.width * 0.45,
        y: rect.minY + rect.height * 0.24,
        width: rect.width * 0.10,
        height: rect.height * 0.17
    ), xRadius: size * 0.018, yRadius: size * 0.018)
    door.fill()
}

private enum IconError: Error {
    case renderFailed
}
