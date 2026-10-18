import SwiftUI
import FrameKitCore

struct CaptureInspector: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Picker("Window", selection: $model.selectedWindowID) {
                    Text("Choose a Window").tag(Optional<CGWindowID>.none)
                    ForEach(model.appWindows) { window in
                        Text(verbatim: window.displayTitle).tag(Optional(window.id))
                    }
                }
                .disabled(model.selectedApp == nil || model.busy)
                if let window = model.selectedWindow {
                    LabeledContent("Current Size", value: window.sizeLabel)
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            } header: {
                Text("Target Window")
            } footer: {
                if model.selectedApp != nil && model.appWindows.isEmpty {
                    Text(model.hasScreenCapture
                         ? String(localized: "Open a regular window on the current desktop, then refresh.")
                         : String(localized: "Allow Screen Recording, then refresh."))
                }
            }

            Section {
                dimensionField(String(localized: "Width"), text: $model.windowWidth, unit: "pt")
                dimensionField(String(localized: "Height"), text: $model.windowHeight, unit: "pt")
                Toggle("Set Position", isOn: $model.changePosition)
                if model.changePosition {
                    dimensionField("X", text: $model.windowX, unit: "pt")
                    dimensionField("Y", text: $model.windowY, unit: "pt")
                }
                HStack {
                    Button("Resize") { Task { await model.resize(andCapture: false) } }
                        .disabled(!model.canResize)
                    Spacer()
                    Button("Resize & Capture") { Task { await model.resize(andCapture: true) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canResize)
                }
            } header: {
                Text("Window Size")
            } footer: {
                Text(model.changePosition
                     ? String(localized: "Size includes the title bar and is measured in points. Coordinates start at the top-left of the main display.")
                     : String(localized: "Size includes the title bar and is measured in points. Set export pixels separately."))
            }
            .disabled(model.busy || model.selectedWindow == nil)

            if let result = model.resizeResult {
                Section("Resize Result") {
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

            Section {
                Toggle("Original Pixel Size", isOn: $model.originalSize)
                if model.originalSize {
                    LabeledContent("Size", value: model.exportConfiguration?.size.label ?? "—")
                        .monospacedDigit().foregroundStyle(.secondary)
                } else {
                    dimensionField(String(localized: "Width"), text: $model.exportWidth, unit: "px")
                    dimensionField(String(localized: "Height"), text: $model.exportHeight, unit: "px")
                    Menu("Common Sizes") {
                        ForEach(["1280×800", "1440×900", "2560×1600", "2880×1800"], id: \.self) { value in
                            Button {
                                let parts = value.split(separator: "×")
                                model.exportWidth = String(parts[0])
                                model.exportHeight = String(parts[1])
                            } label: { Text(verbatim: value) }
                        }
                    }
                    Picker("Scaling", selection: $model.resizeMode) {
                        ForEach(ResizeMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            } header: {
                Text("Export")
            } footer: {
                if !model.originalSize { Text(model.resizeMode.explanation) }
            }
            .disabled(model.busy)

            if model.isUpscaling {
                Text("Exporting at this size enlarges the image without adding detail.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.lastExportURL != nil {
                Button("Show Export in Finder", systemImage: "folder", action: model.showExport)
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
        .scrollContentBackground(.hidden)
    }

    private func dimensionField(_ title: String, text: Binding<String>, unit: String) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                TextField(title, text: text)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 86)
                    .accessibilityLabel(Text(verbatim: "\(title), \(unit)"))
                Text(verbatim: unit).foregroundStyle(.secondary).frame(width: 16, alignment: .leading)
            }
        } label: { Text(verbatim: title) }
    }
}
