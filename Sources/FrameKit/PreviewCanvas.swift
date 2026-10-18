import SwiftUI
import FrameKitCore

struct PreviewCanvas: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            canvas.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let shot = model.capture {
                HStack {
                    Text("原图 \(shot.image.width) × \(shot.image.height) px")
                    Spacer()
                    if let config = model.exportConfiguration { Text("导出 \(config.size.label)") }
                    Text(shot.date, style: .time)
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.vertical, 10)
            }
            if model.previewIsFromEarlierWindowSize {
                Label("窗口已改变，当前预览为之前的截图。请重新截图更新。", systemImage: "arrow.clockwise")
                    .font(.caption).foregroundStyle(.orange).padding(.horizontal, 20).padding(.bottom, 10)
            }
            Divider()
            statusBar
        }
        .background(.background)
    }

    @ViewBuilder
    private var canvas: some View {
        if model.previewBusy {
            ProgressView("正在生成预览…")
        } else if let error = model.previewError {
            ContentUnavailableView("无法生成预览", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if let image = model.renderedPreview {
            GeometryReader { geometry in
                Image(decorative: image, scale: 1)
                    .resizable().interpolation(.high).scaledToFit()
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                    .frame(width: max(1, geometry.size.width - 48), height: max(1, geometry.size.height - 48))
                    .padding(24)
                    .accessibilityLabel("截图导出预览")
            }
        } else {
            ContentUnavailableView {
                Label(model.selectedApp == nil ? "选择一个应用" : "准备截取窗口", systemImage: "macwindow")
            } description: {
                Text(model.selectedApp == nil
                     ? "从侧边栏选择应用，在检查器中设置窗口尺寸。"
                     : "选择具体窗口后，点击工具栏截图，\n或在检查器中调整尺寸并截图。")
            } actions: {
                if model.canCapture {
                    Button("截图", systemImage: "camera") { Task { await model.takeScreenshot() } }
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.busy {
                ProgressView().controlSize(.mini)
            } else if model.messageIsError {
                Image(systemName: "exclamationmark.circle")
            }
            Text(model.busy ? model.activity : model.message)
                .lineLimit(2).help(model.message)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(model.messageIsError && !model.busy ? Color.orange : Color.secondary)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
