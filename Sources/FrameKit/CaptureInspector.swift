import SwiftUI
import FrameKitCore

struct CaptureInspector: View {
    @ObservedObject var model: AppModel
    @State private var sizing: WindowSizing
    var focusedField: FocusState<WindowDimensionField?>.Binding

    init(model: AppModel, focusedField: FocusState<WindowDimensionField?>.Binding) {
        self.model = model
        self.focusedField = focusedField
        _sizing = State(initialValue: model.windowSizing)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Window Size").font(.headline)
                    Picker("Window Size", selection: $sizing) {
                        Text("Current Size").tag(WindowSizing.current)
                        Text("Custom Size").tag(WindowSizing.custom)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if let window = model.selectedWindow {
                        LabeledContent("Current Size", value: window.sizeLabel)
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    if model.windowSizing == .custom {
                        dimensionField(String(localized: "Width"), text: $model.windowWidth, field: .width)
                        dimensionField(String(localized: "Height"), text: $model.windowHeight, field: .height)
                        Toggle("Set Position", isOn: $model.changePosition)
                        if model.changePosition {
                            dimensionField("X", text: $model.windowX, field: .x)
                            dimensionField("Y", text: $model.windowY, field: .y)
                        }
                        if let error = model.windowValidationError {
                            Text(verbatim: error).font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Text(model.windowSizing == .current
                         ? String(localized: "Capture the window as it is. No resizing or Accessibility access is needed.")
                         : String(localized: "The toolbar’s Resize & Capture button applies these values before taking the screenshot. Size includes the title bar and is measured in points."))
                        .font(.caption).foregroundStyle(.secondary)
                    if model.windowSizing == .custom && model.changePosition {
                        Text("Coordinates start at the top-left of the main display. Right and down are positive.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(model.busy)

                if model.windowSizing == .custom && !model.hasAccessibility {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Allow Accessibility", action: model.requestAccessibility)
                        Button("Open System Settings") { model.openPrivacy("Privacy_Accessibility") }
                        Text("Accessibility is only needed to resize or move another app’s window.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let result = model.resizeResult {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Resize Result").font(.headline)
                        Label(result.isExact ? String(localized: "Size Verified") : String(localized: "Partially Applied"),
                              systemImage: result.isExact ? "checkmark.circle" : "exclamationmark.circle")
                            .foregroundStyle(result.isExact ? Color.secondary : Color.orange)
                        LabeledContent("Requested", value: WindowDescriptor.describe(result.requested.size) + " pt")
                        LabeledContent("Actual", value: WindowDescriptor.describe(result.actualFrame.size) + " pt")
                        if result.requested.position != nil {
                            LabeledContent("Position", value: "\(WindowDescriptor.number(result.actualFrame.minX)), \(WindowDescriptor.number(result.actualFrame.minY))")
                        }
                        if !result.isStable { Text("Wait for the layout to settle, then retake.").foregroundStyle(.orange) }
                    }.monospacedDigit()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.small)
        .onSubmit { focusedField.wrappedValue = nil }
        .onExitCommand { focusedField.wrappedValue = nil }
        .task(id: sizing) {
            let selected = sizing
            await Task.yield()
            guard !Task.isCancelled, model.windowSizing != selected else { return }
            model.windowSizing = selected
        }
        .onChange(of: model.windowSizing) { _, value in
            if sizing != value { sizing = value }
        }
    }

    private func dimensionField(_ title: String, text: Binding<String>, field: WindowDimensionField) -> some View {
        HStack {
            Text(verbatim: title)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                TextField(title, text: text)
                    .focused(focusedField, equals: field)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 86)
                    .accessibilityLabel(Text(verbatim: "\(title), pt"))
                Text(verbatim: "pt").foregroundStyle(.secondary)
            }
        }
    }
}
