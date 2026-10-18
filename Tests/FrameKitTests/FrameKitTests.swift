import XCTest
import CoreGraphics
import ImageIO
@testable import FrameKitCore

final class FrameKitTests: XCTestCase {
    func testPixelDimensionsRejectMalformedAndExcessiveValues() throws {
        XCTAssertEqual(try PixelSize(widthText: " 2560 ", heightText: "1600").label, "2560 × 1600 px")
        for text in ["", "12.5", "nan", "0", "-1", "999999999999999999999"] {
            XCTAssertThrowsError(try PixelSize(widthText: text, heightText: "800"))
        }
        XCTAssertThrowsError(try PixelSize(width: 16384, height: 16384))
        XCTAssertThrowsError(try PixelSize(width: .max, height: .max))
    }

    func testWindowRequestAcceptsNegativeScreenCoordinatesButNotNonFiniteSizes() throws {
        let request = try WindowRequest(width: "1280.5", height: "800", x: "-1500", y: "100")
        XCTAssertEqual(request.size.width, 1280.5)
        XCTAssertEqual(request.position, CGPoint(x: -1500, y: 100))
        for text in ["nan", "inf", "-20", "", "17000"] {
            XCTAssertThrowsError(try WindowRequest(width: text, height: "800"))
        }
        XCTAssertThrowsError(try WindowRequest(width: "100", height: "100", x: "nan", y: "1"))
    }

    func testResizeVerificationDoesNotReportClampedOrUnstableResultAsSuccess() throws {
        let request = try WindowRequest(width: "800", height: "500", x: "20", y: "40")
        XCTAssertTrue(ResizeResult(requested: request, actualFrame: CGRect(x: 20, y: 40, width: 800, height: 500), isStable: true).isExact)
        XCTAssertFalse(ResizeResult(requested: request, actualFrame: CGRect(x: 20, y: 40, width: 900, height: 600), isStable: true).isExact)
        XCTAssertFalse(ResizeResult(requested: request, actualFrame: CGRect(x: 21, y: 40, width: 800, height: 500), isStable: true).isExact)
        XCTAssertFalse(ResizeResult(requested: request, actualFrame: CGRect(x: 20, y: 40, width: 800, height: 500), isStable: false).isExact)
    }

    func testWindowMatchingRequiresUniqueGeometryAndNeverUsesTitleAlone() throws {
        let frame = CGRect(x: -1000, y: 50, width: 800, height: 600)
        let target = WindowDescriptor(id: 42, processID: 5, title: "Document", frame: frame)
        let moved = WindowCandidate(title: "Document", frame: frame.offsetBy(dx: 50, dy: 0))
        let correct = WindowCandidate(title: "Document", frame: frame)
        XCTAssertEqual(try WindowMatcher.uniqueIndex(for: target, candidates: [moved, correct]), 1)
        XCTAssertThrowsError(try WindowMatcher.uniqueIndex(for: target, candidates: [moved]))
        XCTAssertThrowsError(try WindowMatcher.uniqueIndex(for: target, candidates: [WindowCandidate(title: "Different document", frame: frame)]))
        XCTAssertThrowsError(try WindowMatcher.uniqueIndex(for: target, candidates: [correct, correct]))
        XCTAssertEqual(try WindowMatcher.uniqueIndex(for: target, candidates: [WindowCandidate(title: "Other", frame: frame), correct]), 1)
    }

    func testFitFillAndStretchGeometry() {
        let source = CGSize(width: 400, height: 200)
        let target = CGSize(width: 100, height: 100)
        XCTAssertEqual(ImageExporter.destinationRect(source: source, target: target, mode: .fit), CGRect(x: 0, y: 25, width: 100, height: 50))
        XCTAssertEqual(ImageExporter.destinationRect(source: source, target: target, mode: .fill), CGRect(x: -50, y: 0, width: 200, height: 100))
        XCTAssertEqual(ImageExporter.destinationRect(source: source, target: target, mode: .stretch), CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    func testRenderedPixelsDistinguishPaddingCroppingAndStretching() throws {
        let source = try stripedImage()
        let size = try PixelSize(width: 100, height: 100)
        let fit = try ImageExporter.render(source, configuration: ExportConfiguration(size: size, mode: .fit))
        let fill = try ImageExporter.render(source, configuration: ExportConfiguration(size: size, mode: .fill))
        let stretch = try ImageExporter.render(source, configuration: ExportConfiguration(size: size, mode: .stretch))
        XCTAssertEqual(pixel(fit, x: 50, y: 5), [255, 255, 255])
        XCTAssertEqual(pixel(fit, x: 5, y: 50), [255, 0, 0])
        XCTAssertEqual(pixel(fill, x: 5, y: 50), [0, 255, 0])
        XCTAssertEqual(pixel(fill, x: 95, y: 50), [0, 255, 0])
        XCTAssertEqual(pixel(stretch, x: 5, y: 5), [255, 0, 0])
        XCTAssertEqual(pixel(stretch, x: 95, y: 95), [0, 0, 255])
    }

    func testPNGHasExactSizeNoAlphaAndCompositesTransparentSource() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let source = try XCTUnwrap(context.makeImage())
        let size = try PixelSize(width: 2880, height: 1800)
        let config = ExportConfiguration(size: size, mode: .fit)
        let image = try ImageExporter.render(source, configuration: config)
        XCTAssertEqual(pixel(image, x: 100, y: 100), [255, 255, 255])
        let data = try ImageExporter.pngData(image, expected: size)
        XCTAssertNoThrow(try ImageExporter.validatePNG(data, expected: size))
        XCTAssertThrowsError(try ImageExporter.validatePNG(data, expected: PixelSize(width: 1280, height: 800)))
        XCTAssertThrowsError(try ImageExporter.validatePNG(Data("invalid".utf8), expected: size))
    }

    func testImageServiceWritesVerifiedPNGToDisk() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("screenshot.png")
        let size = try PixelSize(width: 1440, height: 900)
        let source = try stripedImage()
        try await ImageProcessingService().save(source, configuration: ExportConfiguration(size: size, mode: .fit), to: url)
        XCTAssertNoThrow(try ImageExporter.validatePNG(Data(contentsOf: url), expected: size))
    }

    private func stripedImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColorSpace(CGColorSpace(name: CGColorSpace.sRGB)!)
        context.setFillColor([0, 1, 0, 1])
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        context.setFillColor([1, 0, 0, 1])
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 200))
        context.setFillColor([0, 0, 1, 1])
        context.fill(CGRect(x: 320, y: 0, width: 80, height: 200))
        return try XCTUnwrap(context.makeImage())
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return [] }
        let offset = y * image.bytesPerRow + x * 4
        return [bytes[offset], bytes[offset + 1], bytes[offset + 2]]
    }
}
