import SwiftUI
import FrameKitCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var inspectorPresented = true
    @State private var permissionsPresented = false
    @State private var sidebarSelection: pid_t?

    init(model: AppModel) {
        self.model = model
        _sidebarSelection = State(initialValue: model.selectedAppID)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            applicationSidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            PreviewCanvas(model: model)
                .navigationTitle(Text(verbatim: model.selectedApp?.name ?? "FrameKit"))
                .navigationSubtitle(Text(verbatim: model.selectedWindow?.displayTitle ?? String(localized: "Window Capture")))
                .toolbar { captureToolbar }
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $inspectorPresented) {
            CaptureInspector(model: model)
                .inspectorColumnWidth(min: 280, ideal: 300, max: 340)
        }
        .task { await model.refresh() }
        .task { await model.monitorPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.checkPermissions()
        }
        // The native sidebar can write its selection while SwiftUI updates the
        // List. Keep that write in view state, then commit after this update.
        .task(id: sidebarSelection) {
            let selection = sidebarSelection
            await Task.yield()
            guard !Task.isCancelled else { return }
            model.selectApp(selection)
        }
        .onChange(of: model.selectedAppID) { _, selection in
            if sidebarSelection != selection { sidebarSelection = selection }
        }
        .onChange(of: model.originalSize) { _, _ in model.schedulePreview() }
        .onChange(of: model.exportWidth) { _, _ in model.schedulePreview() }
        .onChange(of: model.exportHeight) { _, _ in model.schedulePreview() }
        .onChange(of: model.resizeMode) { _, _ in model.schedulePreview() }
    }

    private var applicationSidebar: some View {
        List(selection: $sidebarSelection) {
            Section("Running Apps") {
                ForEach(model.apps) { app in
                    HStack(spacing: 9) {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "app").frame(width: 24, height: 24)
                        }
                        Text(verbatim: app.name).lineLimit(1)
                    }
                    .padding(.vertical, 3)
                    .tag(app.id)
                }
            }
        }
        .listStyle(.sidebar)
        .disabled(model.busy)
        .navigationTitle("FrameKit")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.hasAccessibility || !model.hasScreenCapture {
                Button {
                    permissionsPresented = true
                } label: {
                    Label("Set Up Permissions", systemImage: "lock.shield")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(16)
            }
        }
    }

    @ToolbarContentBuilder
    private var captureToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button {
                Task { await model.refresh() }
            } label: {
                Label("Refresh Windows", systemImage: "arrow.clockwise")
            }
            .disabled(model.busy)
            .help("Refresh apps and windows (⌘R)")

            Button {
                permissionsPresented.toggle()
            } label: {
                Label("Permissions", systemImage: model.hasAccessibility && model.hasScreenCapture ? "checkmark.shield" : "lock.shield")
            }
            .help("Permissions")
            .popover(isPresented: $permissionsPresented, arrowEdge: .bottom) {
                PermissionView(model: model)
            }
        }
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await model.takeScreenshot() }
            } label: {
                Label(model.capture == nil ? String(localized: "Capture") : String(localized: "Retake"), systemImage: "camera")
            }
            .disabled(!model.canCapture)
            .help("Capture at the current window size (⌘K)")

            Button {
                Task { await model.export() }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(model.capture == nil || model.exportConfiguration == nil || model.previewBusy || model.busy)
            .help("Export PNG (⌘E)")
        }
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
        }
        ToolbarItem(placement: .automatic) {
            Button {
                inspectorPresented.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help(inspectorPresented ? String(localized: "Hide Inspector") : String(localized: "Show Inspector"))
        }
    }
}
