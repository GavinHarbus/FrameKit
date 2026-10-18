import SwiftUI
import FrameKitCore

struct PreviewCanvas: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            canvas.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let shot = model.capture {
                HStack {
                    Text("Original \(shot.image.width) × \(shot.image.height) px")
                    Spacer()
                    if let config = model.exportConfiguration { Text("Export \(config.size.label)") }
                    Text(shot.date, style: .time)
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .padding(.horizontal, 20).padding(.vertical, 10)
            }
            if model.previewIsFromEarlierWindowSize {
                Label("The window has changed. This preview shows the previous capture. Retake to update it.", systemImage: "arrow.clockwise")
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
            ProgressView("Generating preview…")
        } else if let error = model.previewError {
            ContentUnavailableView("Preview Unavailable", systemImage: "exclamationmark.triangle", description: Text(verbatim: error))
        } else if let image = model.renderedPreview {
            GeometryReader { geometry in
                Image(decorative: image, scale: 1)
                    .resizable().interpolation(.high).scaledToFit()
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                    .frame(width: max(1, geometry.size.width - 48), height: max(1, geometry.size.height - 48))
                    .padding(24)
                    .accessibilityLabel("Screenshot export preview")
            }
        } else {
            ContentUnavailableView {
                Label(model.selectedApp == nil ? String(localized: "Choose an App") : String(localized: "Ready to Capture"), systemImage: "macwindow")
            } description: {
                Text(model.selectedApp == nil
                     ? String(localized: "Select an app in the sidebar, then set its window size in the inspector.")
                     : String(localized: "Choose a window, then capture from the toolbar\nor resize and capture from the inspector."))
            } actions: {
                if model.canCapture {
                    Button("Capture", systemImage: "camera") { Task { await model.takeScreenshot() } }
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
            Text(verbatim: model.busy ? model.activity : model.message)
                .lineLimit(2).help(model.message)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(model.messageIsError && !model.busy ? Color.orange : Color.secondary)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
