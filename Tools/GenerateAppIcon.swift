import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Run from the repository root: swift Tools/GenerateAppIcon.swift
// This preparation is specific to the supplied blue tile on a white presentation
// background. The original and the white artwork inside the tile stay intact.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let original = root.appendingPathComponent("Design/FrameKit-logo-original.png")
let assets = root.appendingPathComponent("Resources/Assets.xcassets")
let iconSet = assets.appendingPathComponent("AppIcon.appiconset")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard let source = CGImageSourceCreateWithURL(original as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let space = CGColorSpace(name: CGColorSpace.sRGB) else { fail("Cannot read original logo.") }
let width = image.width
let height = image.height
guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: width * 4, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let storage = context.data else { fail("Cannot allocate logo canvas.") }
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
let pixels = Array(UnsafeBufferPointer(start: storage.assumingMemoryBound(to: UInt8.self), count: width * height * 4))

// Locate the outer blue tile, including the white interior artwork.
var left = [Int](repeating: width, count: height)
var right = [Int](repeating: -1, count: height)
var topAtX = [Int](repeating: height, count: width)
var bottomAtX = [Int](repeating: -1, count: width)
for y in 0..<height {
    for x in 0..<width {
        let i = (y * width + x) * 4
        if Int(pixels[i + 2]) - Int(pixels[i]) >= 70 {
            left[y] = min(left[y], x)
            right[y] = max(right[y], x)
            topAtX[x] = min(topAtX[x], y)
            bottomAtX[x] = max(bottomAtX[x], y)
        }
    }
}
let rows = (0..<height).filter { right[$0] >= left[$0] }
guard let top = rows.first, let bottom = rows.last else { fail("Cannot locate the blue logo tile.") }
let minX = rows.map { left[$0] }.min()!
let maxX = rows.map { right[$0] }.max()!

func isInterior(_ x: Int, _ y: Int, inset: Int = 3) -> Bool {
    guard y >= inset, y < height - inset else { return false }
    for row in (y - inset)...(y + inset) {
        if x < left[row] + inset || x > right[row] - inset { return false }
    }
    return true
}

var cutout = [UInt8](repeating: 0, count: pixels.count)
for y in max(0, top - 4)...min(height - 1, bottom + 4) {
    for x in max(0, minX - 4)...min(width - 1, maxX + 4) {
        let i = (y * width + x) * 4
        if isInterior(x, y) {
            cutout[i] = pixels[i]
            cutout[i + 1] = pixels[i + 1]
            cutout[i + 2] = pixels[i + 2]
            cutout[i + 3] = 255
            continue
        }
        // Discard the presentation shadow outside the silhouette, including its blue tint.
        let touchesTile = (max(0, y - 1)...min(height - 1, y + 1)).contains { row in
            x >= left[row] - 1 && x <= right[row] + 1
        }
        guard touchesTile else { continue }
        // Recover edge antialiasing from blue/red contrast, avoiding a white halo.
        var nearest: (index: Int, distance: Int)?
        func consider(_ sx: Int, _ sy: Int) {
            guard sx >= 0, sx < width, sy >= 0, sy < height, isInterior(sx, sy) else { return }
            let distance = (sx - x) * (sx - x) + (sy - y) * (sy - y)
            if distance <= 256, nearest == nil || distance < nearest!.distance {
                nearest = ((sy * width + sx) * 4, distance)
            }
        }
        for sy in max(top, y - 12)...min(bottom, y + 12) {
            let lower = left[sy] + 6
            let upper = right[sy] - 6
            if lower <= upper { consider(min(max(x, lower), upper), sy) }
        }
        for sx in max(minX, x - 12)...min(maxX, x + 12) {
            let lower = topAtX[sx] + 6
            let upper = bottomAtX[sx] - 6
            if lower <= upper { consider(sx, min(max(y, lower), upper)) }
        }
        guard let nearest else { continue }
        let contrast = max(0, Int(pixels[i + 2]) - Int(pixels[i]))
        guard contrast > 6 else { continue }
        let foreground = nearest.index
        let fullContrast = max(1, Int(pixels[foreground + 2]) - Int(pixels[foreground]))
        let alpha = min(1.0, Double(contrast) / Double(fullContrast))
        for channel in 0..<3 {
            cutout[i + channel] = UInt8((Double(pixels[foreground + channel]) * alpha).rounded())
        }
        cutout[i + 3] = UInt8((alpha * 255).rounded())
    }
}

guard let provider = CGDataProvider(data: Data(cutout) as CFData),
      let transparent = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: true,
                                intent: .defaultIntent) else { fail("Cannot create transparent logo.") }

// Center the tile with transparent breathing room for the Dock and Finder.
let padding = 4
let cropRect = CGRect(x: minX - padding, y: top - padding,
                      width: maxX - minX + 1 + padding * 2, height: bottom - top + 1 + padding * 2)
guard let cropped = transparent.cropping(to: cropRect),
      let masterContext = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fail("Cannot create master icon.")
}
let scale = 824.0 / Double(max(maxX - minX + 1, bottom - top + 1))
let outputWidth = Double(cropped.width) * scale
let outputHeight = Double(cropped.height) * scale
masterContext.interpolationQuality = .high
masterContext.draw(cropped, in: CGRect(x: (1024 - outputWidth) / 2, y: (1024 - outputHeight) / 2,
                                       width: outputWidth, height: outputHeight))
guard let master = masterContext.makeImage() else { fail("Cannot render master icon.") }

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("Cannot create \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("Cannot encode \(url.path)") }
}

try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
writePNG(master, to: root.appendingPathComponent("Design/FrameKit-AppIcon.png"))
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
        writePNG(output.makeImage()!, to: iconSet.appendingPathComponent(name))
        entries.append(["filename": name, "idiom": "mac", "size": "\(size)x\(size)", "scale": "\(density)x"])
    }
}
let info: [String: Any] = ["author": "xcode", "version": 1]
try JSONSerialization.data(withJSONObject: ["images": entries, "info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appendingPathComponent("Contents.json"))
try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: assets.appendingPathComponent("Contents.json"))
print("Generated 10 macOS app icon assets and Design/FrameKit-AppIcon.png.")
