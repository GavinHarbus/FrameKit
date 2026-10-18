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
            throw FrameKitError(String(localized: "Not enough memory to render the image. Reduce the export size.", bundle: AppLocalization.bundle))
        }
        // Export has no background setting. Fit padding and transparent corners are white.
        context.setFillColorSpace(space)
        context.setFillColor([1, 1, 1, 1])
        context.fill(CGRect(origin: .zero, size: size.cgSize))
        context.interpolationQuality = .high
        context.draw(source, in: destinationRect(source: CGSize(width: source.width, height: source.height),
                                                 target: size.cgSize, mode: configuration.mode))
        guard let image = context.makeImage() else { throw FrameKitError(String(localized: "Could not render the export image.", bundle: AppLocalization.bundle)) }
        return image
    }

    /// Encode and inspect the actual PNG, not just the requested drawing dimensions.
    public static func pngData(_ image: CGImage, expected: PixelSize) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw FrameKitError(String(localized: "Could not create the PNG file.", bundle: AppLocalization.bundle))
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FrameKitError(String(localized: "PNG encoding failed.", bundle: AppLocalization.bundle)) }
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
            throw FrameKitError(String(localized: "Export verification failed: the file dimensions, format, or alpha channel do not match the settings.", bundle: AppLocalization.bundle))
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
