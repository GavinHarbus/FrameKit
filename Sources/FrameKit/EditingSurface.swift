import AppKit
import SwiftUI

enum WindowDimensionField: Hashable { case width, height, x, y }

/// Bridges the two native window behaviors SwiftUI does not expose directly:
/// ending text editing on a click outside an input, and titlebar separator style.
struct EditingSurface: NSViewRepresentable {
    var hidesTitlebarSeparator = false
    var onEndEditing: () -> Void

    func makeNSView(context: Context) -> EditingSurfaceView {
        let view = EditingSurfaceView()
        view.onEndEditing = onEndEditing
        view.hidesTitlebarSeparator = hidesTitlebarSeparator
        return view
    }

    func updateNSView(_ view: EditingSurfaceView, context: Context) {
        view.onEndEditing = onEndEditing
        view.hidesTitlebarSeparator = hidesTitlebarSeparator
        view.updateWindowAppearance()
    }

    static func dismantleNSView(_ view: EditingSurfaceView, coordinator: ()) {
        view.stopMonitoring()
    }
}

@MainActor
final class EditingSurfaceView: NSView {
    var onEndEditing: () -> Void = {}
    var hidesTitlebarSeparator = false
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        updateWindowAppearance()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleMouseDown(event)
            // Never consume the click: buttons, selections, and split view drags still work.
            return event
        }
    }

    func updateWindowAppearance() {
        if hidesTitlebarSeparator, let window, window.titlebarSeparatorStyle != .none {
            window.titlebarSeparatorStyle = .none
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func handleMouseDown(_ event: NSEvent) {
        guard let window, event.window === window,
              let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
              let root = window.contentView?.superview else { return }
        let point = root.convert(event.locationInWindow, from: nil)
        let hit = root.hitTest(point)
        guard !Self.isTextInput(hit) else { return }
        // Commit the field editor before the original event reaches its button or blank area.
        if window.makeFirstResponder(nil) { onEndEditing() }
    }

    private static func isTextInput(_ view: NSView?) -> Bool {
        var current = view
        while let candidate = current {
            if let field = candidate as? NSTextField, field.isEditable || field.isSelectable { return true }
            if let text = candidate as? NSTextView, text.isEditable || text.isSelectable { return true }
            current = candidate.superview
        }
        return false
    }
}
