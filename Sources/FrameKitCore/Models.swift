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
            throw FrameKitError("图片宽高须为 1–16384 的整数像素。")
        }
        guard width * height <= Self.maximumPixels else {
            throw FrameKitError("图片总像素不能超过 6400 万，请减小导出尺寸。")
        }
        self.width = width
        self.height = height
    }

    public init(widthText: String, heightText: String) throws {
        guard let width = Int(widthText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let height = Int(heightText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw FrameKitError("请输入整数像素宽高，例如 2560 × 1600。")
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

    public var displayTitle: String { title.isEmpty ? "未命名窗口 #\(id)" : title }
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
            throw FrameKitError("窗口宽高须为 1–16384 的有效数值，单位是逻辑点。")
        }
        size = CGSize(width: width, height: height)
        if let x, let y {
            guard let px = number(x), let py = number(y), px.isFinite, py.isFinite,
                  abs(px) <= 100_000, abs(py) <= 100_000 else {
                throw FrameKitError("请输入有效的屏幕坐标。")
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
                throw FrameKitError("窗口标题与控制接口不一致，已停止调整。请刷新后重试，或直接截图。")
            }
            return index
        }
        if geometryMatches.count > 1, !target.title.isEmpty {
            let titleMatches = geometryMatches.filter { candidates[$0].title == target.title }
            if titleMatches.count == 1 { return titleMatches[0] }
        }
        if geometryMatches.isEmpty {
            throw FrameKitError("无法关联这个窗口的控制接口。请刷新窗口列表后重试；仍失败时可直接截图。")
        }
        throw FrameKitError("多个窗口的位置、尺寸和标题无法区分。请先手动移开目标窗口，再刷新重试。")
    }
}

public enum ResizeMode: String, CaseIterable, Codable, Sendable {
    case fit, fill, stretch
    public var title: String {
        switch self { case .fit: return "等比留白"; case .fill: return "居中裁剪"; case .stretch: return "拉伸" }
    }
    public var explanation: String {
        switch self {
        case .fit: return "保留完整画面，多余区域留白。"
        case .fill: return "填满画布，居中裁去超出部分。"
        case .stretch: return "填满画布，会改变原图比例。"
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
