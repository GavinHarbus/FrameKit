import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageExporter {
    public static func destinationRect(source: CGSize, target: CGSize, mode: ResizeMode) -> CGRect {
        guard source.width > 0, source.height > 0 else { return .zero }
        if mode == .stretch { return CGRect(origin: .zero, size: target) }
        let ratio = mode == .fit
            ? min(target.width / source.width, target.height / source.height)
            : max(target.width / source.width, target.height / source.height)
        let size = CGSize(width: source.width * ratio, height: source.height * ratio)
        return CGRect(x: (target.width - size.width) / 2, y: (target.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    public static func render(_ source: CGImage, configuration: ExportConfiguration) throws -> CGImage {
        let size = configuration.size
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size.width, height: size.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw FrameKitError("无法分配图片内存，请减小导出尺寸。")
        }
        // Export has no background setting. Fit padding and transparent corners are white.
        context.setFillColorSpace(space)
        context.setFillColor([1, 1, 1, 1])
        context.fill(CGRect(origin: .zero, size: size.cgSize))
        context.interpolationQuality = .high
        context.draw(source, in: destinationRect(source: CGSize(width: source.width, height: source.height),
                                                 target: size.cgSize, mode: configuration.mode))
        guard let image = context.makeImage() else { throw FrameKitError("无法生成导出图片。") }
        return image
    }

    /// Encode and inspect the actual PNG, not just the requested drawing dimensions.
    public static func pngData(_ image: CGImage, expected: PixelSize) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw FrameKitError("无法创建 PNG 文件。")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FrameKitError("PNG 编码失败。") }
        let result = data as Data
        try validatePNG(result, expected: expected)
        return result
    }

    public static func validatePNG(_ data: Data, expected: PixelSize) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == expected.width,
              (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == expected.height,
              (properties[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue != true else {
            throw FrameKitError("导出校验失败：文件的尺寸、格式或透明通道不符合设置。")
        }
    }
}

/// Image work is serialized off the main actor; a large export does not block the UI.
public actor ImageProcessingService {
    public init() {}
    public func preview(_ source: CGImage, configuration: ExportConfiguration) throws -> CGImage {
        try Task.checkCancellation()
        // Preview uses the same full-resolution render as export, so crop and padding agree exactly.
        return try ImageExporter.render(source, configuration: configuration)
    }
    public func save(_ source: CGImage, configuration: ExportConfiguration, to url: URL) throws {
        let image = try ImageExporter.render(source, configuration: configuration)
        let data = try ImageExporter.pngData(image, expected: configuration.size)
        try data.write(to: url, options: .atomic)
        try ImageExporter.validatePNG(Data(contentsOf: url), expected: configuration.size)
    }
}
