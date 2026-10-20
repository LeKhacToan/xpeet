#!/usr/bin/env swift
// Builds the mascot image sets from the Stitch renders (specs/ui-redesign R1).
// Usage: scripts/mascot-assets.swift <folder with calm.png, happy.png, …, blink.png>
// Each 1024 px render is cropped to its badge's bounding square, resized to 288 px and saved as JPEG 0.8.
// Run by hand when the artwork changes; not part of the build. Sources are listed in Xpeet/Resources/MASCOT-SOURCE.txt.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let assets = ["calm", "happy", "worried", "startled", "sleepy", "searching", "sad", "blink"]
/// Badge centre and radius as fractions of the render's side. Override per asset if a render is off-centre.
let defaultBadge = (x: 0.5, y: 0.5, radius: 0.42)
let badgeOverrides: [String: (x: Double, y: Double, radius: Double)] = [:]
let outputSide = 288
let quality = 0.8

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    print("usage: mascot-assets.swift <renders folder>")
    exit(64)
}
let source = URL(fileURLWithPath: arguments[1])
let catalog = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("../Xpeet/Resources/Assets.xcassets/Mascot")
    .standardizedFileURL

func write(_ json: String, to url: URL) throws {
    try json.write(to: url, atomically: true, encoding: .utf8)
}

try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
try write("""
{
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "provides-namespace" : true }
}

""", to: catalog.appendingPathComponent("Contents.json"))

for name in assets {
    let input = source.appendingPathComponent("\(name).png")
    guard let imageSource = CGImageSourceCreateWithURL(input as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        print("missing or unreadable: \(input.path)")
        exit(1)
    }
    let side = Double(min(image.width, image.height))
    let badge = badgeOverrides[name] ?? defaultBadge
    let crop = CGRect(
        x: (badge.x - badge.radius) * side,
        y: (badge.y - badge.radius) * side,
        width: badge.radius * 2 * side,
        height: badge.radius * 2 * side
    ).integral
    guard let cropped = image.cropping(to: crop),
          let context = CGContext(
              data: nil, width: outputSide, height: outputSide, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          ) else {
        print("could not crop \(name)")
        exit(1)
    }
    context.interpolationQuality = .high
    context.draw(cropped, in: CGRect(x: 0, y: 0, width: outputSide, height: outputSide))
    guard let resized = context.makeImage() else { exit(1) }

    let set = catalog.appendingPathComponent("\(name).imageset")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    let output = set.appendingPathComponent("\(name).jpg")
    guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
        exit(1)
    }
    CGImageDestinationAddImage(destination, resized, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { exit(1) }
    try write("""
    {
      "images" : [ { "filename" : "\(name).jpg", "idiom" : "universal" } ],
      "info" : { "author" : "xcode", "version" : 1 }
    }

    """, to: set.appendingPathComponent("Contents.json"))
    print("\(name): \(try FileManager.default.attributesOfItem(atPath: output.path)[.size] ?? 0) bytes")
}
