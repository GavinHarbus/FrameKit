import Foundation
import CoreGraphics

public struct FrameKitError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct PixelSize: Equatable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    public static let maximumEdge = 16_384
    public static let maximumPixels = 64_000_000

    public init(width: Int, height: Int) throws {
        guard width > 0, height > 0, width <= Self.maximumEdge, height <= Self.maximumEdge else {
            throw FrameKitError(String(localized: "Image width and height must be whole pixels from 1 to 16384.", bundle: AppLocalization.bundle))
        }
        guard width * height <= Self.maximumPixels else {
            throw FrameKitError(String(localized: "The image cannot exceed 64 million pixels. Reduce the export size.", bundle: AppLocalization.bundle))
        }
        self.width = width
        self.height = height
    }

    public init(widthText: String, heightText: String) throws {
        guard let width = Int(widthText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let height = Int(heightText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw FrameKitError(String(localized: "Enter whole-pixel dimensions, such as 2560 × 1600.", bundle: AppLocalization.bundle))
        }
        try self.init(width: width, height: height)
    }

    public var cgSize: CGSize { CGSize(width: width, height: height) }
    public var label: String { "\(width) × \(height) px" }
}

public struct WindowDescriptor: Identifiable, Equatable, Sendable {
    public let id: CGWindowID
    public let processID: pid_t
    public let title: String
    public let frame: CGRect

    public init(id: CGWindowID, processID: pid_t, title: String, frame: CGRect) {
        self.id = id
        self.processID = processID
        self.title = title
        self.frame = frame
    }

    public var displayTitle: String {
        title.isEmpty ? String(localized: "Untitled Window #\(String(id))", bundle: AppLocalization.bundle) : title
    }
    public var sizeLabel: String { Self.describe(frame.size) + " pt" }
    public static func describe(_ size: CGSize) -> String {
        "\(number(size.width)) × \(number(size.height))"
    }
    public static func number(_ value: CGFloat) -> String {
        value.rounded() == value ? String(format: "%.0f", Double(value)) : String(format: "%.1f", Double(value))
    }
}

public struct WindowRequest: Sendable {
    public let size: CGSize
    public let position: CGPoint?

    public init(width: String, height: String, x: String? = nil, y: String? = nil) throws {
        func number(_ text: String) -> Double? {
            Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let width = number(width), let height = number(height),
              width.isFinite, height.isFinite, width >= 1, height >= 1,
              width <= 16_384, height <= 16_384 else {
            throw FrameKitError(String(localized: "Window width and height must be valid numbers from 1 to 16384 points.", bundle: AppLocalization.bundle))
        }
        size = CGSize(width: width, height: height)
        if let x, let y {
            guard let px = number(x), let py = number(y), px.isFinite, py.isFinite,
                  abs(px) <= 100_000, abs(py) <= 100_000 else {
                throw FrameKitError(String(localized: "Enter valid screen coordinates.", bundle: AppLocalization.bundle))
            }
            position = CGPoint(x: px, y: py)
        } else {
            position = nil
        }
    }
}

public struct ResizeResult: Sendable {
    public let requested: WindowRequest
    public let actualFrame: CGRect
    public let isStable: Bool
    public init(requested: WindowRequest, actualFrame: CGRect, isStable: Bool) {
        self.requested = requested
        self.actualFrame = actualFrame
        self.isStable = isStable
    }
    public var reachedRequestedSize: Bool {
        abs(actualFrame.width - requested.size.width) <= 0.5 &&
        abs(actualFrame.height - requested.size.height) <= 0.5
    }
    public var reachedRequestedPosition: Bool {
        guard let position = requested.position else { return true }
        return abs(actualFrame.minX - position.x) <= 0.5 && abs(actualFrame.minY - position.y) <= 0.5
    }
    public var isExact: Bool { reachedRequestedSize && reachedRequestedPosition && isStable }
}

public struct WindowCandidate: Sendable {
    public let title: String
    public let frame: CGRect
    public init(title: String, frame: CGRect) { self.title = title; self.frame = frame }
}

public enum WindowMatcher {
    public static func sameFrame(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance &&
        abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }

    /// Never fall back to a frontmost window or a title-only match: either may target another document.
    public static func uniqueIndex(for target: WindowDescriptor, candidates: [WindowCandidate]) throws -> Int {
        let geometryMatches = candidates.indices.filter { sameFrame(target.frame, candidates[$0].frame) }
        if geometryMatches.count == 1 {
            let index = geometryMatches[0]
            if !target.title.isEmpty, !candidates[index].title.isEmpty, target.title != candidates[index].title {
                throw FrameKitError(String(localized: "The window title does not match its controls, so resizing was stopped. Refresh and try again, or capture directly.", bundle: AppLocalization.bundle))
            }
            return index
        }
        if geometryMatches.count > 1, !target.title.isEmpty {
            let titleMatches = geometryMatches.filter { candidates[$0].title == target.title }
            if titleMatches.count == 1 { return titleMatches[0] }
        }
        if geometryMatches.isEmpty {
            throw FrameKitError(String(localized: "Could not match the window to its controls. Refresh and try again. If it still fails, capture directly.", bundle: AppLocalization.bundle))
        }
        throw FrameKitError(String(localized: "Multiple windows have indistinguishable positions, sizes, and titles. Move the target window, then refresh and try again.", bundle: AppLocalization.bundle))
    }
}

public enum ResizeMode: String, CaseIterable, Codable, Sendable {
    case fit, fill, stretch
    public var title: String {
        switch self {
        case .fit: return String(localized: "Fit", bundle: AppLocalization.bundle)
        case .fill: return String(localized: "Fill", bundle: AppLocalization.bundle)
        case .stretch: return String(localized: "Stretch", bundle: AppLocalization.bundle)
        }
    }
    public var explanation: String {
        switch self {
        case .fit: return String(localized: "Keep the entire image and add white padding.", bundle: AppLocalization.bundle)
        case .fill: return String(localized: "Fill the canvas and crop the edges from the center.", bundle: AppLocalization.bundle)
        case .stretch: return String(localized: "Fill the canvas by changing the image proportions.", bundle: AppLocalization.bundle)
        }
    }
}

public struct ExportConfiguration: Equatable, Sendable {
    public let size: PixelSize
    public let mode: ResizeMode
    public init(size: PixelSize, mode: ResizeMode) {
        self.size = size; self.mode = mode
    }
}
