import SwiftUI
import FrameKitCore

struct CaptureInspector: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Picker("窗口", selection: $model.selectedWindowID) {
                    Text("选择窗口").tag(Optional<CGWindowID>.none)
                    ForEach(model.appWindows) { window in
                        Text(window.displayTitle).tag(Optional(window.id))
                    }
                }
                .disabled(model.selectedApp == nil || model.busy)
                if let window = model.selectedWindow {
                    LabeledContent("当前尺寸", value: window.sizeLabel)
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            } header: {
                Text("目标窗口")
            } footer: {
                if model.selectedApp != nil && model.appWindows.isEmpty {
                    Text(model.hasScreenCapture ? "请打开普通窗口，恢复到当前桌面后刷新。" : "请先允许屏幕录制，然后刷新。")
                }
            }

            Section {
                dimensionField("宽度", text: $model.windowWidth, unit: "pt")
                dimensionField("高度", text: $model.windowHeight, unit: "pt")
                Toggle("设置位置", isOn: $model.changePosition)
                if model.changePosition {
                    dimensionField("X", text: $model.windowX, unit: "pt")
                    dimensionField("Y", text: $model.windowY, unit: "pt")
                }
                HStack {
                    Button("仅调整") { Task { await model.resize(andCapture: false) } }
                        .disabled(!model.canResize)
                    Spacer()
                    Button("调整并截图") { Task { await model.resize(andCapture: true) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canResize)
                }
            } header: {
                Text("窗口尺寸")
            } footer: {
                Text(model.changePosition
                     ? "外框含标题栏，单位为逻辑点。坐标以主屏左上角为原点。"
                     : "外框含标题栏，单位为逻辑点。导出像素单独设置。")
            }
            .disabled(model.busy || model.selectedWindow == nil)

            if let result = model.resizeResult {
                Section("调整结果") {
                    Label(result.isExact ? "实际尺寸已验证" : "请求未完全生效",
                          systemImage: result.isExact ? "checkmark.circle" : "exclamationmark.circle")
                        .foregroundStyle(result.isExact ? Color.secondary : Color.orange)
                    LabeledContent("请求", value: WindowDescriptor.describe(result.requested.size) + " pt")
                    LabeledContent("实际", value: WindowDescriptor.describe(result.actualFrame.size) + " pt")
                    if result.requested.position != nil {
                        LabeledContent("坐标", value: "\(WindowDescriptor.number(result.actualFrame.minX)), \(WindowDescriptor.number(result.actualFrame.minY))")
                    }
                    if !result.isStable { Text("布局尚未稳定，请等待后重拍。").foregroundStyle(.orange) }
                }.monospacedDigit()
            }

            Section {
                Toggle("原图像素尺寸", isOn: $model.originalSize)
                if model.originalSize {
                    LabeledContent("尺寸", value: model.exportConfiguration?.size.label ?? "—")
                        .monospacedDigit().foregroundStyle(.secondary)
                } else {
                    dimensionField("宽度", text: $model.exportWidth, unit: "px")
                    dimensionField("高度", text: $model.exportHeight, unit: "px")
                    Menu("常用尺寸") {
                        ForEach(["1280×800", "1440×900", "2560×1600", "2880×1800"], id: \.self) { value in
                            Button(value) {
                                let parts = value.split(separator: "×")
                                model.exportWidth = String(parts[0])
                                model.exportHeight = String(parts[1])
                            }
                        }
                    }
                    Picker("缩放", selection: $model.resizeMode) {
                        ForEach(ResizeMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            } header: {
                Text("导出")
            } footer: {
                if !model.originalSize { Text(model.resizeMode.explanation) }
            }
            .disabled(model.busy)

            if model.isUpscaling {
                Text("导出会放大原图，无法增加真实细节。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.lastExportURL != nil {
                Button("在 Finder 中显示导出文件", systemImage: "folder", action: model.showExport)
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
        .scrollContentBackground(.hidden)
    }

    private func dimensionField(_ title: String, text: Binding<String>, unit: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, text: text)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 86)
                    .accessibilityLabel("\(title)，\(unit)")
                Text(unit).foregroundStyle(.secondary).frame(width: 16, alignment: .leading)
            }
        }
    }
}
