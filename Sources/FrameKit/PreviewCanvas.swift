import SwiftUI
import FrameKitCore

struct PreviewCanvas: View {
    @ObservedObject var model: AppModel
    @State private var outputSizePresented = false

    var body: some View {
        VStack(spacing: 0) {
            if let shot = model.capture {
                HStack {
                    Text(verbatim: shot.window.displayTitle).font(.headline).lineLimit(1)
                    Spacer()
                    Button { outputSizePresented.toggle() } label: {
                        Label("Output Size", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .disabled(model.busy)
                    .popover(isPresented: $outputSizePresented) { OutputSizeView(model: model) }
                }.padding(.horizontal, 20).padding(.vertical, 12)
            }
            canvas.frame(maxWidth: .infinity, maxHeight: .infinity)
            if let shot = model.capture {
                VStack(alignment: .leading, spacing: 8) {
                    if let error = model.outputValidationError {
                        HStack {
                            Text(verbatim: error).foregroundStyle(.orange)
                            Spacer()
                            Button("Edit Output Size") { outputSizePresented = true }
                        }
                    } else if !model.previewMatchesOutput {
                        Text(model.previewBusy ? String(localized: "Updating output preview…")
                             : String(localized: "The preview shows the previous output settings."))
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Original \(String(shot.image.width)) × \(String(shot.image.height)) px")
                        Spacer()
                        if let config = model.renderedConfiguration { Text("Output \(config.size.label)") }
                    }.monospacedDigit().foregroundStyle(.secondary)
                    HStack {
                        Label(model.isCurrentExported ? String(localized: "Exported") : String(localized: "Not Exported"),
                              systemImage: model.isCurrentExported ? "checkmark.circle" : "circle")
                        if model.isCurrentExported {
                            Button("Show Export in Finder", action: model.showExport).buttonStyle(.link)
                        }
                        Spacer()
                    }
                    Text("Export before switching windows or quitting. Screenshots are not saved automatically.")
                        .foregroundStyle(.secondary)
                    if model.previewIsFromEarlierWindowSize {
                        Label("The window has changed. This preview shows the previous capture. Retake to update it.", systemImage: "arrow.clockwise")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption).padding(.horizontal, 20).padding(.vertical, 12)
            }
            statusBar
        }
    }

    @ViewBuilder
    private var canvas: some View {
        if let image = model.renderedPreview ?? model.capture?.image {
            GeometryReader { geometry in
                Image(decorative: image, scale: 1)
                    .resizable().interpolation(.high).scaledToFit()
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                    .frame(width: max(1, geometry.size.width - 48), height: max(1, geometry.size.height - 48))
                    .padding(24)
                    .accessibilityLabel("Screenshot export preview")
            }
            .overlay(alignment: .topTrailing) {
                if model.previewBusy { ProgressView().controlSize(.small).padding(16) }
            }
            .overlay(alignment: .bottom) {
                if let error = model.previewError {
                    Text(verbatim: error).font(.caption).foregroundStyle(.orange).padding(12)
                }
            }
        } else if model.isRefreshing {
            ProgressView("Loading apps and windows…")
        } else if !model.hasScreenCapture {
            ContentUnavailableView {
                Label("Allow Screen Recording", systemImage: "macwindow")
            } description: {
                Text("FrameKit needs access to list your windows and capture the one you select.")
            } actions: {
                Button("Request Access", action: model.requestScreenCapture).buttonStyle(.borderedProminent)
                Button("Open System Settings") { model.openPrivacy("Privacy_ScreenCapture") }
            }
        } else if model.selectedApp == nil {
            ContentUnavailableView("Choose an App", systemImage: "app.dashed",
                                   description: Text("Select an app in the sidebar to see its windows."))
        } else if model.appWindows.isEmpty {
            ContentUnavailableView("No Available Windows", systemImage: "macwindow",
                                   description: Text("Open a regular window on the current desktop. The list refreshes when you return to FrameKit."))
        } else if model.selectedWindow == nil {
            ContentUnavailableView("Choose a Window", systemImage: "macwindow",
                                   description: Text("Choose the target window below the app list."))
        } else if model.windowSizing == .custom && !model.hasAccessibility {
            ContentUnavailableView {
                Label("Allow Accessibility", systemImage: "accessibility")
            } description: {
                Text("Accessibility is needed to apply your custom window size. Current Size captures without resizing.")
            } actions: {
                Button("Request Access", action: model.requestAccessibility).buttonStyle(.borderedProminent)
                Button("Open System Settings") { model.openPrivacy("Privacy_Accessibility") }
            }
        } else {
            ContentUnavailableView("Ready to Capture", systemImage: "macwindow",
                                   description: Text(model.windowSizing == .current
                                                     ? String(localized: "Click Capture in the toolbar to take a screenshot at the current window size.")
                                                     : String(localized: "Set the window dimensions in the inspector, then click Resize & Capture in the toolbar.")))
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.busy { ProgressView().controlSize(.mini) }
            else if model.messageIsError { Image(systemName: "exclamationmark.circle") }
            Text(verbatim: model.busy ? model.activity : model.message).lineLimit(2).help(model.message)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(model.messageIsError && !model.busy ? Color.orange : Color.secondary)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
