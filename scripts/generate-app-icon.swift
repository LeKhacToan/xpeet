// Draws the 1024x1024 app icon: a dark green-black tile with a pastel-green 270° arc gauge.
// Usage: swift scripts/generate-app-icon.swift [output.png]  (default output is resolved from the repo root)
// Colours follow Palette in Xpeet/Features/Speedometer/SpeedometerView.swift; the icon uses a lighter centre
// and adds a tip knob and hub so it reads at small sizes.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Xpeet/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
        .path

func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
// Opaque bitmap: the App Store rejects icons with an alpha channel.
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!

let side = CGFloat(size)
let center = CGPoint(x: side / 2, y: side / 2 - 10)

// Background: radial gradient, slightly lighter in the middle.
let background = CGGradient(colorsSpace: space, colors: [rgb(0x1C2E23), rgb(0x0A0F0C)] as CFArray, locations: [0, 1])!
context.drawRadialGradient(
    background, startCenter: center, startRadius: 0, endCenter: center, endRadius: side * 0.72,
    options: .drawsAfterEndLocation
)

// Arc geometry. CoreGraphics is y-up: 225° is the lower left, clockwise runs over the top to -45° (lower right).
let radius: CGFloat = 330
let lineWidth: CGFloat = 96
let startAngle: CGFloat = 225
let sweep: CGFloat = 270
let filled: CGFloat = 0.66

func arcPath(to fraction: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let end = startAngle - sweep * fraction
    path.addArc(
        center: center, radius: radius,
        startAngle: startAngle * .pi / 180, endAngle: end * .pi / 180, clockwise: true
    )
    return path.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

// Track.
context.addPath(arcPath(to: 1))
context.setFillColor(rgb(0xFFFFFF, alpha: 0.1))
context.fillPath()

// Glow under the progress arc.
context.saveGState()
context.setShadow(offset: .zero, blur: 60, color: rgb(0x9FE3B5, alpha: 0.6))
context.addPath(arcPath(to: filled))
context.setFillColor(rgb(0x9FE3B5))
context.fillPath()
context.restoreGState()

// Progress arc with the fixed brand gradient, deep mint at the lower left to pastel green at the upper right.
context.saveGState()
context.addPath(arcPath(to: filled))
context.clip()
let brand = CGGradient(colorsSpace: space, colors: [rgb(0x6CCB97), rgb(0x9FE3B5)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(
    brand, start: CGPoint(x: center.x - radius, y: center.y - radius),
    end: CGPoint(x: center.x + radius, y: center.y + radius), options: []
)
context.restoreGState()

// Knob at the tip of the progress arc.
let tipAngle = (startAngle - sweep * filled) * .pi / 180
let tip = CGPoint(x: center.x + radius * cos(tipAngle), y: center.y + radius * sin(tipAngle))
let knob: CGFloat = lineWidth * 0.32
context.setFillColor(rgb(0xFFFFFF))
context.fillEllipse(in: CGRect(x: tip.x - knob, y: tip.y - knob, width: knob * 2, height: knob * 2))

// Hub in the middle.
let hub: CGFloat = 46
context.setFillColor(rgb(0x9FE3B5))
context.fillEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2))

let image = context.makeImage()!
let url = URL(fileURLWithPath: output)
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(output)") }
print("wrote \(output)")
