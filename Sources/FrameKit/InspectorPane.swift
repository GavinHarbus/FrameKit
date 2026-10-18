import AppKit
import SwiftUI

/// An inset inspector separates controls with material and space rather than a
/// full-height split-view rule. Its leading gutter remains a resize target.
struct InspectorPane<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var width: CGFloat = 300
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        HStack(spacing: 0) {
            InspectorResizeHandle()
                .frame(width: 10)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragStartWidth == nil { dragStartWidth = width }
                            width = clamped((dragStartWidth ?? width) - value.translation.width)
                        }
                        .onEnded { _ in dragStartWidth = nil }
                )
                .accessibilityElement()
                .accessibilityLabel("Resize Inspector")
                .accessibilityValue(Text("\(Int(width)) points"))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: width = clamped(width + 20)
                    case .decrement: width = clamped(width - 20)
                    @unknown default: break
                    }
                }

            panel
                .frame(width: width)
        }
        .padding(.vertical, 12)
        .padding(.trailing, 12)
    }

    @ViewBuilder
    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if #available(macOS 26.0, *) {
            content()
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
        } else {
            content()
                .background(.regularMaterial, in: shape)
                .clipShape(shape)
        }
    }

    private func clamped(_ value: CGFloat) -> CGFloat { min(340, max(280, value)) }
}

private struct InspectorResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ nsView: CursorView, context: Context) {}

    final class CursorView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }
    }
}

struct ContinuousToolbarBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content.toolbarBackground(.hidden, for: .windowToolbar)
        }
    }
}

private struct InspectorVisibilityKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var inspectorVisibility: Binding<Bool>? {
        get { self[InspectorVisibilityKey.self] }
        set { self[InspectorVisibilityKey.self] = newValue }
    }
}

struct InspectorPaneCommands: Commands {
    @FocusedBinding(\.inspectorVisibility) private var isPresented

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(isPresented == true ? String(localized: "Hide Inspector") : String(localized: "Show Inspector")) {
                isPresented?.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(isPresented == nil)
        }
    }
}
