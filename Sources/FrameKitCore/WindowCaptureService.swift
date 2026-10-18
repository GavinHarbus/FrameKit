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
            throw FrameKitError(String(localized: "Allow Screen Recording to list and capture windows. Then refresh, or reopen FrameKit if macOS asks.", bundle: AppLocalization.bundle))
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
            throw FrameKitError(String(localized: "The selected window was closed, hidden, or minimized. Restore it to the current desktop, then refresh and select it again.", bundle: AppLocalization.bundle))
        }
        return window
    }

    public func current(_ selected: WindowDescriptor) async throws -> WindowDescriptor {
        let window = try await resolve(id: selected.id, processID: selected.processID)
        guard let value = descriptor(window) else { throw FrameKitError(String(localized: "The selected window is unavailable.", bundle: AppLocalization.bundle)) }
        return value
    }

    public func capture(_ selected: WindowDescriptor, expectedFrame: CGRect? = nil) async throws -> CapturedWindow {
        let window = try await resolve(id: selected.id, processID: selected.processID)
        guard let current = descriptor(window) else { throw FrameKitError(String(localized: "The selected window is unavailable.", bundle: AppLocalization.bundle)) }
        if let expectedFrame, !WindowMatcher.sameFrame(current.frame, expectedFrame) {
            throw FrameKitError(String(localized: "The window changed after resizing, so capture was stopped. Refresh and try again, or capture at its current size.", bundle: AppLocalization.bundle))
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = filter.pointPixelScale
        let bounds = filter.contentRect
        guard scale.isFinite, scale > 0, bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0,
              bounds.width * CGFloat(scale) <= CGFloat(PixelSize.maximumEdge),
              bounds.height * CGFloat(scale) <= CGFloat(PixelSize.maximumEdge) else {
            throw FrameKitError(String(localized: "The capture dimensions are invalid or too large. Resize the window and try again.", bundle: AppLocalization.bundle))
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
            throw FrameKitError(String(localized: "The window moved or resized during capture. Wait for it to settle, then retake.", bundle: AppLocalization.bundle))
        }
        return CapturedWindow(image: image, window: after, scale: scale)
    }
}
