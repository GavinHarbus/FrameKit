import ApplicationServices
import Foundation

public actor AccessibilityWindowService {
    public init() {}

    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    private func frame(_ element: AXUIElement) throws -> CGRect {
        guard let position = attribute(element, kAXPositionAttribute),
              let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            throw FrameKitError("目标应用没有提供可读取的窗口尺寸或位置。")
        }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.height > 0 else {
            throw FrameKitError("目标应用返回了无效的窗口尺寸。")
        }
        return CGRect(origin: point, size: dimensions)
    }

    private func resolve(_ selected: WindowDescriptor) throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw FrameKitError("请先在系统设置中授予 FrameKit 辅助功能权限。") }
        let app = AXUIElementCreateApplication(selected.processID)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let elements = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else {
            throw FrameKitError("目标应用没有提供窗口控制接口，仍可尝试直接截图。")
        }
        let candidates: [(AXUIElement, WindowCandidate)] = elements.compactMap { element in
            AXUIElementSetMessagingTimeout(element, 1)
            guard (attribute(element, kAXMinimizedAttribute) as? Bool) != true,
                  let bounds = try? frame(element) else { return nil }
            return (element, WindowCandidate(title: attribute(element, kAXTitleAttribute) as? String ?? "", frame: bounds))
        }
        let index = try WindowMatcher.uniqueIndex(for: selected, candidates: candidates.map { $0.1 })
        return candidates[index].0
    }

    private func requireWritable(_ element: AXUIElement, _ key: String, label: String) throws {
        var writable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, key as CFString, &writable) == .success, writable.boolValue else {
            throw FrameKitError("这个窗口不允许修改\(label)。请退出全屏或选择普通窗口；也可以直接截图。")
        }
    }

    private func check(_ result: AXError, action: String) throws {
        guard result == .success else {
            throw FrameKitError("\(action)未完成（AX \(result.rawValue)）。窗口可能已部分改变，请刷新确认实际尺寸后重试。")
        }
    }

    public func resize(_ selected: WindowDescriptor, request: WindowRequest) async throws -> ResizeResult {
        let element = try resolve(selected)
        try requireWritable(element, kAXSizeAttribute, label: "尺寸")
        if request.position != nil { try requireWritable(element, kAXPositionAttribute, label: "位置") }
        // Check the original geometry again immediately before writing.
        guard WindowMatcher.sameFrame(try frame(element), selected.frame) else {
            throw FrameKitError("窗口刚刚发生变化，请刷新后重新调整。")
        }
        var size = request.size
        guard let sizeValue = AXValueCreate(.cgSize, &size) else { throw FrameKitError("无法创建窗口尺寸。") }
        try check(AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue), action: "调整尺寸")
        if var point = request.position {
            guard let value = AXValueCreate(.cgPoint, &point) else { throw FrameKitError("无法创建窗口坐标。") }
            try check(AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value), action: "调整位置")
        }
        var previous = try frame(element)
        var stableReadings = 0
        // Multiple readbacks handle asynchronous layout and app-enforced minimum dimensions.
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(150))
            let current = try frame(element)
            stableReadings = WindowMatcher.sameFrame(previous, current, tolerance: 0.1) ? stableReadings + 1 : 0
            previous = current
            if stableReadings >= 3 {
                return ResizeResult(requested: request, actualFrame: current, isStable: true)
            }
        }
        return ResizeResult(requested: request, actualFrame: previous, isStable: false)
    }
}
