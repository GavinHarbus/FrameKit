import Foundation
import ScreenCaptureKit
import CoreGraphics

public struct CapturedWindow {
    public let id = UUID()
    public let image: CGImage
    public let window: WindowDescriptor
    public let date = Date()
    public let scale: Float
}

public actor WindowCaptureService {
    public init() {}

    private func content() async throws -> SCShareableContent {
        guard CGPreflightScreenCaptureAccess() else {
            throw FrameKitError("请先允许屏幕录制，以读取窗口列表和截图。授权后点击刷新；系统要求时重新打开 FrameKit。")
        }
        return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    }

    private func descriptor(_ window: SCWindow) -> WindowDescriptor? {
        guard let app = window.owningApplication, window.windowLayer == 0,
              window.isOnScreen, window.frame.width > 1, window.frame.height > 1 else { return nil }
        return WindowDescriptor(id: window.windowID, processID: app.processID,
                                title: window.title ?? "", frame: window.frame)
    }

    public func windows() async throws -> [WindowDescriptor] {
        try await content().windows.compactMap(descriptor)
            .filter { $0.processID != ProcessInfo.processInfo.processIdentifier }
            .sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }

    private func resolve(id: CGWindowID, processID: pid_t) async throws -> SCWindow {
        let windows = try await content().windows
        guard let window = windows.first(where: {
            $0.windowID == id && $0.owningApplication?.processID == processID && descriptor($0) != nil
        }) else {
            throw FrameKitError("所选窗口已关闭、隐藏或最小化。请将它恢复到当前桌面，再刷新选择。")
        }
        return window
    }

    public func current(_ selected: WindowDescriptor) async throws -> WindowDescriptor {
        let window = try await resolve(id: selected.id, processID: selected.processID)
        guard let value = descriptor(window) else { throw FrameKitError("所选窗口不可用。") }
        return value
    }

    public func capture(_ selected: WindowDescriptor, expectedFrame: CGRect? = nil) async throws -> CapturedWindow {
        let window = try await resolve(id: selected.id, processID: selected.processID)
        guard let current = descriptor(window) else { throw FrameKitError("所选窗口不可用。") }
        if let expectedFrame, !WindowMatcher.sameFrame(current.frame, expectedFrame) {
            throw FrameKitError("窗口在调整后又发生了变化，已停止截图。请刷新并重试，或直接截取当前窗口。")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = filter.pointPixelScale
        let bounds = filter.contentRect
        guard scale.isFinite, scale > 0, bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0,
              bounds.width * CGFloat(scale) <= CGFloat(PixelSize.maximumEdge),
              bounds.height * CGFloat(scale) <= CGFloat(PixelSize.maximumEdge) else {
            throw FrameKitError("窗口的捕获尺寸无效或过大，请减小窗口后重试。")
        }
        let size = try PixelSize(width: Int((bounds.width * CGFloat(scale)).rounded()),
                                 height: Int((bounds.height * CGFloat(scale)).rounded()))
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .best
        configuration.scalesToFit = false
        configuration.preservesAspectRatio = true
        configuration.colorSpaceName = CGColorSpace.sRGB
        // ScreenCaptureKit exposes this property as assign, so retain the color through the async call.
        let background = CGColor(gray: 0, alpha: 0)
        configuration.backgroundColor = background
        defer { withExtendedLifetime(background) {} }
        if #available(macOS 14.2, *) { configuration.includeChildWindows = false }
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        // If the target changes during the asynchronous capture, never label an uncertain frame as verified.
        let after = try await self.current(current)
        guard WindowMatcher.sameFrame(current.frame, after.frame, tolerance: 0.5) else {
            throw FrameKitError("截图过程中窗口尺寸或位置改变，请等待窗口稳定后重拍。")
        }
        return CapturedWindow(image: image, window: after, scale: scale)
    }
}
