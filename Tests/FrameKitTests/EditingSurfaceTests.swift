import AppKit
import XCTest

final class EditingSurfaceTests: XCTestCase {
    @MainActor
    private func fixture() throws -> (NSWindow, NSTextField, EditingSurfaceView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let content = try XCTUnwrap(window.contentView)
        let field = NSTextField(frame: NSRect(x: 20, y: 200, width: 100, height: 24))
        field.stringValue = "800"
        content.addSubview(field)
        let surface = EditingSurfaceView(frame: .zero)
        content.addSubview(surface)
        XCTAssertTrue(window.makeFirstResponder(field))
        return (window, field, surface)
    }

    @MainActor
    private func click(_ point: NSPoint, in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                                         timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                         eventNumber: 1, clickCount: 1, pressure: 1))
    }

    @MainActor
    func testClickingBlankSpaceEndsEditingAndCommitsText() throws {
        let (window, field, surface) = try fixture()
        var ended = false
        surface.onEndEditing = { ended = true }
        defer { surface.stopMonitoring(); window.orderOut(nil) }
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.string = "1440"
        surface.handleMouseDown(try click(NSPoint(x: 200, y: 100), in: window))
        XCTAssertTrue(ended)
        XCTAssertEqual(field.stringValue, "1440")
        XCTAssertFalse((window.firstResponder as? NSTextView)?.isFieldEditor == true)
    }

    @MainActor
    func testClickInsideInputDoesNotDismissEditing() throws {
        let (window, _, surface) = try fixture()
        var ended = false
        surface.onEndEditing = { ended = true }
        defer { surface.stopMonitoring(); window.orderOut(nil) }
        surface.handleMouseDown(try click(NSPoint(x: 50, y: 212), in: window))
        XCTAssertFalse(ended)
        XCTAssertTrue((window.firstResponder as? NSTextView)?.isFieldEditor == true)
    }

    @MainActor
    func testClickInAnotherWindowDoesNotAffectEditing() throws {
        let (window, _, surface) = try fixture()
        let other = NSWindow(contentRect: NSRect(x: 400, y: 0, width: 200, height: 200),
                             styleMask: [.titled], backing: .buffered, defer: false)
        var ended = false
        surface.onEndEditing = { ended = true }
        defer { surface.stopMonitoring(); window.orderOut(nil); other.orderOut(nil) }
        surface.handleMouseDown(try click(NSPoint(x: 50, y: 50), in: other))
        XCTAssertFalse(ended)
        XCTAssertTrue((window.firstResponder as? NSTextView)?.isFieldEditor == true)
    }
}
