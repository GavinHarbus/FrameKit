import Combine
import XCTest
import FrameKitCore

final class AppSelectionTests: XCTestCase {
    @MainActor
    private func model() -> AppModel {
        let permissions = PermissionMonitor(
            read: { PermissionSnapshot(accessibility: false, screenCapture: false) },
            requestAccessibility: {}, requestScreenCapture: {}
        )
        let model = AppModel(permissions: permissions)
        model.apps = [RunningApp(id: 100, name: "First", icon: nil), RunningApp(id: 200, name: "Second", icon: nil)]
        model.windows = [
            WindowDescriptor(id: 10, processID: 100, title: "One", frame: CGRect(x: 20, y: 40, width: 800, height: 600)),
            WindowDescriptor(id: 20, processID: 200, title: "Two", frame: CGRect(x: 50, y: 80, width: 1000, height: 700)),
            WindowDescriptor(id: 21, processID: 200, title: "Three", frame: CGRect(x: 60, y: 90, width: 1200, height: 900))
        ]
        return model
    }

    @MainActor
    func testAppSelectionResolvesSingleWindowAndLoadsItsGeometry() {
        let model = model()
        model.selectApp(100)
        XCTAssertEqual(model.selectedAppID, 100)
        XCTAssertEqual(model.selectedWindowID, 10)
        XCTAssertEqual(model.windowWidth, "800")
        XCTAssertEqual(model.windowHeight, "600")
        XCTAssertEqual(model.windowX, "20")
        XCTAssertEqual(model.windowY, "40")
    }

    @MainActor
    func testRepeatedSelectionDoesNotPublishOrOverwriteUserEdits() {
        let model = model()
        model.selectApp(100)
        model.windowWidth = "1440"
        var publications = 0
        let subscription = model.objectWillChange.sink { publications += 1 }
        model.selectApp(100)
        model.selectWindow(10)
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(model.windowWidth, "1440")
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testSwitchingAppsRejectsAStaleWindowSelection() {
        let model = model()
        model.selectApp(100)
        model.selectApp(200)
        XCTAssertNil(model.selectedWindowID, "Multiple windows must require an explicit selection.")
        model.selectWindow(10)
        XCTAssertNil(model.selectedWindowID, "A delayed selection from another app must not be applied.")
        model.selectWindow(21)
        XCTAssertEqual(model.selectedWindowID, 21)
        XCTAssertEqual(model.windowWidth, "1200")
        XCTAssertEqual(model.windowHeight, "900")
    }

    @MainActor
    func testClearingAndInvalidSelectionsKeepTheModelConsistent() {
        let model = model()
        model.selectApp(100)
        model.selectApp(999)
        XCTAssertEqual(model.selectedAppID, 100)
        model.selectWindow(999)
        XCTAssertEqual(model.selectedWindowID, 10)
        model.selectApp(nil)
        XCTAssertNil(model.selectedAppID)
        XCTAssertNil(model.selectedWindowID)
        XCTAssertNil(model.capture)
        XCTAssertNil(model.renderedPreview)
        XCTAssertFalse(model.canResize)
        XCTAssertFalse(model.canCapture)
    }
}
