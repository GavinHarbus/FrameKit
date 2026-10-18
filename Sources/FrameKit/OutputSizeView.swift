import SwiftUI
import FrameKitCore

struct OutputSizeView: View {
    @ObservedObject var model: AppModel
    @State private var original: Bool
    @State private var mode: ResizeMode

    init(model: AppModel) {
        self.model = model
        _original = State(initialValue: model.originalSize)
        _mode = State(initialValue: model.resizeMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Output Size").font(.headline)
            Picker("Output Size", selection: $original) {
                Text("Original").tag(true)
                Text("Custom").tag(false)
            }.pickerStyle(.segmented).labelsHidden()
            if model.originalSize {
                Text("Save the original screenshot dimensions. Export only asks where to save the PNG.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 12) {
                    field(String(localized: "Width"), text: $model.exportWidth)
                    field(String(localized: "Height"), text: $model.exportHeight)
                }
                if let error = model.outputValidationError {
                    Text(verbatim: error).font(.caption).foregroundStyle(.orange)
                }
                Menu("Common Sizes") {
                    ForEach(["1280×800", "1440×900", "2560×1600", "2880×1800"], id: \.self) { value in
                        Button {
                            let parts = value.split(separator: "×")
                            model.exportWidth = String(parts[0])
                            model.exportHeight = String(parts[1])
                        } label: { Text(verbatim: value) }
                    }
                }
                Picker("Scaling", selection: $mode) {
                    ForEach(ResizeMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Text(model.resizeMode.explanation).font(.caption).foregroundStyle(.secondary)
            }
            if let config = model.exportConfiguration {
                LabeledContent("Output", value: config.size.label).monospacedDigit()
            }
            if model.isUpscaling {
                Text("Exporting at this size enlarges the image without adding detail.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20).frame(width: 340)
        .disabled(model.busy)
        .task(id: original) {
            let selected = original
            await Task.yield()
            guard !Task.isCancelled, model.originalSize != selected else { return }
            model.originalSize = selected
        }
        .task(id: mode) {
            let selected = mode
            await Task.yield()
            guard !Task.isCancelled, model.resizeMode != selected else { return }
            model.resizeMode = selected
        }
        .onChange(of: model.originalSize) { _, value in if original != value { original = value } }
        .onChange(of: model.resizeMode) { _, value in if mode != value { mode = value } }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField(title, text: text).labelsHidden().textFieldStyle(.roundedBorder)
                    .monospacedDigit().accessibilityLabel(Text(verbatim: "\(title), px"))
                Text(verbatim: "px").foregroundStyle(.secondary)
            }
        }
    }
}
