import SwiftUI
import FrameKitCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var inspectorPresented = true
    @State private var permissionsPresented = false
    @State private var sidebarSelection: pid_t?
    @State private var windowSelection: CGWindowID?
    @FocusState private var focusedDimension: WindowDimensionField?

    init(model: AppModel) {
        self.model = model
        _sidebarSelection = State(initialValue: model.selectedAppID)
        _windowSelection = State(initialValue: model.selectedWindowID)
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
            CaptureInspector(model: model, focusedField: $focusedDimension)
                .inspectorColumnWidth(min: 280, ideal: 300, max: 340)
        }
        .background(EditingSurface(hidesTitlebarSeparator: true) { focusedDimension = nil })
        .task { await model.refresh() }
        .task { await model.monitorPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.checkPermissions()
            model.requestRefresh()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            model.requestRefresh()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            model.requestRefresh()
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
        .task(id: windowSelection) {
            let selection = windowSelection
            let appID = model.selectedAppID
            await Task.yield()
            guard !Task.isCancelled, appID == model.selectedAppID else { return }
            model.selectWindow(selection)
        }
        .onChange(of: model.selectedWindowID) { _, selection in
            if windowSelection != selection { windowSelection = selection }
        }
        .task(id: model.previewRequest) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            model.schedulePreview()
        }
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
            VStack(alignment: .leading, spacing: 10) {
                if model.selectedApp != nil {
                    Text("Target Window").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Window", selection: $windowSelection) {
                        Text("Choose a Window").tag(Optional<CGWindowID>.none)
                        ForEach(model.appWindows) { window in
                            Text(verbatim: window.displayTitle).tag(Optional(window.id))
                        }
                    }
                    .labelsHidden()
                    .disabled(model.busy || model.isRefreshing || model.appWindows.isEmpty)
                    if let window = model.selectedWindow {
                        Text(verbatim: window.sizeLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                if !model.hasAccessibility || !model.hasScreenCapture {
                    Button { permissionsPresented = true } label: {
                        Label("Set Up Permissions", systemImage: "lock.shield")
                    }.buttonStyle(.plain)
                }
            }.padding(16)
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
            .disabled(model.busy || model.isRefreshing)
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
                Task { await model.performCapture() }
            } label: {
                Label(model.captureActionTitle, systemImage: "camera")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(!model.canPerformCapture)
            .help(model.windowSizing == .current
                  ? String(localized: "Capture at the current window size (⌘K)")
                  : String(localized: "Apply the custom window size, verify it, and capture (⌘K)"))

            Button {
                Task { await model.export() }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up").labelStyle(.titleAndIcon)
            }
            .disabled(!model.canExport)
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
