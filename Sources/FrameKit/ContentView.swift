import SwiftUI
import FrameKitCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var inspectorPresented = true
    @State private var permissionsPresented = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            applicationSidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            PreviewCanvas(model: model)
                .navigationTitle(model.selectedApp?.name ?? "FrameKit")
                .navigationSubtitle(model.selectedWindow?.displayTitle ?? "窗口截图")
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
        .onChange(of: model.selectedAppID) { _, _ in model.appSelectionChanged() }
        .onChange(of: model.selectedWindowID) { _, _ in model.windowSelectionChanged() }
        .onChange(of: model.originalSize) { _, _ in model.schedulePreview() }
        .onChange(of: model.exportWidth) { _, _ in model.schedulePreview() }
        .onChange(of: model.exportHeight) { _, _ in model.schedulePreview() }
        .onChange(of: model.resizeMode) { _, _ in model.schedulePreview() }
    }

    private var applicationSidebar: some View {
        List(selection: $model.selectedAppID) {
            Section("运行中的应用") {
                ForEach(model.apps) { app in
                    HStack(spacing: 9) {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "app").frame(width: 24, height: 24)
                        }
                        Text(app.name).lineLimit(1)
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
                    Label("设置系统权限", systemImage: "lock.shield")
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
                Label("刷新窗口", systemImage: "arrow.clockwise")
            }
            .disabled(model.busy)
            .help("刷新应用与窗口（⌘R）")

            Button {
                permissionsPresented.toggle()
            } label: {
                Label("系统权限", systemImage: model.hasAccessibility && model.hasScreenCapture ? "checkmark.shield" : "lock.shield")
            }
            .help("系统权限")
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
                Label(model.capture == nil ? "截图" : "重拍", systemImage: "camera")
            }
            .disabled(!model.canCapture)
            .help("按当前窗口尺寸截图（⌘K）")

            Button {
                Task { await model.export() }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .disabled(model.capture == nil || model.exportConfiguration == nil || model.previewBusy || model.busy)
            .help("导出 PNG（⌘E）")
        }
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed)
        }
        ToolbarItem(placement: .automatic) {
            Button {
                inspectorPresented.toggle()
            } label: {
                Label("检查器", systemImage: "sidebar.right")
            }
            .help(inspectorPresented ? "隐藏检查器" : "显示检查器")
        }
    }
}
