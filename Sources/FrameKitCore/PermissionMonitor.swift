import AppKit
import ApplicationServices
import Combine
import Foundation

public struct PermissionSnapshot: Equatable, Sendable {
    public let accessibility: Bool
    public let screenCapture: Bool

    public init(accessibility: Bool, screenCapture: Bool) {
        self.accessibility = accessibility
        self.screenCapture = screenCapture
    }
}

/// Only reads the OS result. Asking for access never optimistically grants it.
@MainActor
public final class PermissionMonitor: ObservableObject {
    @Published public private(set) var snapshot = PermissionSnapshot(accessibility: false, screenCapture: false)
    private let read: () -> PermissionSnapshot
    private let requestAccessibilityAccess: () -> Void
    private let requestScreenCaptureAccess: () -> Void
    private var waitingUntil = Date.distantPast

    public init(
        read: @escaping () -> PermissionSnapshot = {
            PermissionSnapshot(accessibility: AXIsProcessTrustedWithOptions(nil),
                               screenCapture: CGPreflightScreenCaptureAccess())
        },
        requestAccessibility: @escaping () -> Void = {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        },
        requestScreenCapture: @escaping () -> Void = { _ = CGRequestScreenCaptureAccess() }
    ) {
        self.read = read
        requestAccessibilityAccess = requestAccessibility
        requestScreenCaptureAccess = requestScreenCapture
    }

    public func refresh() {
        let latest = read()
        if latest != snapshot { snapshot = latest }
    }

    public func requestAccessibility() {
        watchForSettingsChanges()
        requestAccessibilityAccess()
        // The system prompt is asynchronous. This is just the initial result; polling follows.
        refresh()
    }

    public func requestScreenCapture() {
        watchForSettingsChanges()
        requestScreenCaptureAccess()
        refresh()
    }

    public func watchForSettingsChanges() {
        waitingUntil = Date().addingTimeInterval(120)
    }

    /// Runs for the view's lifetime. Poll while foregrounded or while the user is in Settings.
    /// Cancellation on view disappearance avoids leaving timers or observers behind.
    public func monitor(
        interval: Duration = .seconds(1),
        isActive: @escaping @MainActor () -> Bool = { NSApp?.isActive == true }
    ) async {
        while !Task.isCancelled {
            if isActive() || Date() < waitingUntil { refresh() }
            do { try await Task.sleep(for: interval) } catch { return }
        }
    }
}
