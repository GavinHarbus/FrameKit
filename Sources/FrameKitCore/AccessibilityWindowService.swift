import ApplicationServices
import Foundation

public protocol WindowResizing: Sendable {
    func resize(_ selected: WindowDescriptor, request: WindowRequest) async throws -> ResizeResult
}

public actor AccessibilityWindowService: WindowResizing {
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
            throw FrameKitError(String(localized: "The app does not provide a readable window size or position.", bundle: AppLocalization.bundle))
        }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.height > 0 else {
            throw FrameKitError(String(localized: "The app returned invalid window dimensions.", bundle: AppLocalization.bundle))
        }
        return CGRect(origin: point, size: dimensions)
    }

    private func resolve(_ selected: WindowDescriptor) throws -> AXUIElement {
        guard AXIsProcessTrusted() else { throw FrameKitError(String(localized: "Allow Accessibility access for FrameKit in System Settings first.", bundle: AppLocalization.bundle)) }
        let app = AXUIElementCreateApplication(selected.processID)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let elements = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else {
            throw FrameKitError(String(localized: "The app does not provide window controls. You can still try capturing it.", bundle: AppLocalization.bundle))
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

    private func requireWritable(_ element: AXUIElement, _ key: String) throws {
        var writable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, key as CFString, &writable) == .success, writable.boolValue else {
            if key == kAXSizeAttribute {
                throw FrameKitError(String(localized: "This window cannot be resized. Exit full screen or choose a regular window, or capture directly.", bundle: AppLocalization.bundle))
            }
            throw FrameKitError(String(localized: "This window cannot be moved. Exit full screen or choose a regular window, or capture directly.", bundle: AppLocalization.bundle))
        }
    }

    private func check(_ result: AXError, moving: Bool = false) throws {
        guard result == .success else {
            if moving {
                throw FrameKitError(String(localized: "Move failed (AX \(String(result.rawValue))). The window may have partially changed. Refresh to check its actual size before retrying.", bundle: AppLocalization.bundle))
            }
            throw FrameKitError(String(localized: "Resize failed (AX \(String(result.rawValue))). The window may have partially changed. Refresh to check its actual size before retrying.", bundle: AppLocalization.bundle))
        }
    }

    public func resize(_ selected: WindowDescriptor, request: WindowRequest) async throws -> ResizeResult {
        let element = try resolve(selected)
        try requireWritable(element, kAXSizeAttribute)
        if request.position != nil { try requireWritable(element, kAXPositionAttribute) }
        // Check the original geometry again immediately before writing.
        guard WindowMatcher.sameFrame(try frame(element), selected.frame) else {
            throw FrameKitError(String(localized: "The window just changed. Refresh before resizing again.", bundle: AppLocalization.bundle))
        }
        var size = request.size
        guard let sizeValue = AXValueCreate(.cgSize, &size) else { throw FrameKitError(String(localized: "Could not create the window size value.", bundle: AppLocalization.bundle)) }
        try check(AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue))
        if var point = request.position {
            guard let value = AXValueCreate(.cgPoint, &point) else { throw FrameKitError(String(localized: "Could not create the window position value.", bundle: AppLocalization.bundle)) }
            try check(AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value), moving: true)
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
