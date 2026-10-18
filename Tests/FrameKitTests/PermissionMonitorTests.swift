import Combine
import XCTest
@testable import FrameKitCore

final class PermissionMonitorTests: XCTestCase {
    @MainActor
    func testRequestDoesNotPretendAnAsynchronousGrantHasCompleted() {
        var actual = PermissionSnapshot(accessibility: false, screenCapture: true)
        var requests = 0
        let monitor = PermissionMonitor(read: { actual }, requestAccessibility: { requests += 1 }, requestScreenCapture: {})
        monitor.requestAccessibility()
        XCTAssertEqual(requests, 1)
        XCTAssertFalse(monitor.snapshot.accessibility)
        XCTAssertTrue(monitor.snapshot.screenCapture)

        actual = PermissionSnapshot(accessibility: true, screenCapture: true)
        monitor.refresh()
        XCTAssertTrue(monitor.snapshot.accessibility)

        actual = PermissionSnapshot(accessibility: false, screenCapture: true)
        monitor.refresh()
        XCTAssertFalse(monitor.snapshot.accessibility, "Revocation must disable window control again.")
    }

    @MainActor
    func testGrantUpdatesWhileUserIsStillInSystemSettings() async {
        var actual = PermissionSnapshot(accessibility: false, screenCapture: false)
        var requestCount = 0
        let monitor = PermissionMonitor(read: { actual }, requestAccessibility: { requestCount += 1 }, requestScreenCapture: {})
        monitor.requestAccessibility()
        let granted = expectation(description: "Grant is published without returning focus or pressing Refresh")
        let subscription = monitor.$snapshot.dropFirst().filter { $0.accessibility }.prefix(1).sink { _ in granted.fulfill() }
        let task = Task { await monitor.monitor(interval: .milliseconds(10), isActive: { false }) }
        actual = PermissionSnapshot(accessibility: true, screenCapture: false)
        await fulfillment(of: [granted], timeout: 2)
        task.cancel()
        await task.value
        XCTAssertEqual(requestCount, 1, "Polling must not trigger more system permission prompts.")
        XCTAssertFalse(monitor.snapshot.screenCapture, "One permission must not imply the other.")
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testForegroundPollingObservesRevocationAndStopsOnCancellation() async {
        var actual = PermissionSnapshot(accessibility: true, screenCapture: true)
        var reads = 0
        let monitor = PermissionMonitor(read: { reads += 1; return actual }, requestAccessibility: {}, requestScreenCapture: {})
        monitor.refresh()
        let revoked = expectation(description: "Revocation is published")
        let subscription = monitor.$snapshot.dropFirst().filter { !$0.accessibility }.prefix(1).sink { _ in revoked.fulfill() }
        let task = Task { await monitor.monitor(interval: .milliseconds(10), isActive: { true }) }
        actual = PermissionSnapshot(accessibility: false, screenCapture: true)
        await fulfillment(of: [revoked], timeout: 2)
        task.cancel()
        await task.value
        let readsAtCancellation = reads
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(reads, readsAtCancellation)
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testUnchangedPermissionChecksDoNotRepublishUIState() {
        let monitor = PermissionMonitor(read: { PermissionSnapshot(accessibility: true, screenCapture: false) },
                                        requestAccessibility: {}, requestScreenCapture: {})
        var changes = 0
        let subscription = monitor.$snapshot.dropFirst().sink { _ in changes += 1 }
        monitor.refresh()
        monitor.refresh()
        monitor.refresh()
        XCTAssertEqual(changes, 1)
        withExtendedLifetime(subscription) {}
    }
}
