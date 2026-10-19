import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Run from the repository root: swift Tools/GenerateAppIcon.swift
// Regenerate the macOS catalog from the public, prepared icon master.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let masterURL = root.appendingPathComponent("Design/FrameKit-AppIcon.png")
let iconSet = root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard let source = CGImageSourceCreateWithURL(masterURL as CFURL, nil),
      let master = CGImageSourceCreateImageAtIndex(source, 0, nil),
      master.width == 1024, master.height == 1024,
      let space = CGColorSpace(name: CGColorSpace.sRGB) else {
    fail("Expected a 1024 × 1024 icon master at Design/FrameKit-AppIcon.png.")
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("Cannot create \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("Cannot encode \(url.path)") }
}

try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
var entries: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for density in [1, 2] {
        let pixels = size * density
        let name = "icon_\(size)x\(size)\(density == 2 ? "@2x" : "").png"
        guard let output = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                     bytesPerRow: 0, space: space,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("Cannot resize icon.") }
        output.interpolationQuality = .high
        output.draw(master, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        guard let image = output.makeImage() else { fail("Cannot render icon.") }
        writePNG(image, to: iconSet.appendingPathComponent(name))
        entries.append(["filename": name, "idiom": "mac", "size": "\(size)x\(size)", "scale": "\(density)x"])
    }
}
let info: [String: Any] = ["author": "xcode", "version": 1]
try JSONSerialization.data(withJSONObject: ["images": entries, "info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appendingPathComponent("Contents.json"))
print("Generated 10 macOS app icon assets from Design/FrameKit-AppIcon.png.")
