import AppKit
import ApplicationServices
import Combine
import FrameKitCore
import SwiftUI
import UniformTypeIdentifiers

struct RunningApp: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage?
}

enum WindowSizing: String, CaseIterable { case current, custom }

struct PreviewRequest: Equatable {
    let captureID: UUID?
    let originalSize: Bool
    let width: String
    let height: String
    let mode: ResizeMode
}

struct ExportReceipt {
    let captureID: UUID
    let configuration: ExportConfiguration
    let url: URL
}

@MainActor
final class AppModel: ObservableObject {
    @Published var apps: [RunningApp] = []
    @Published var windows: [WindowDescriptor] = []
    @Published private(set) var selectedAppID: pid_t?
    @Published private(set) var selectedWindowID: CGWindowID?
    @Published private(set) var hasAccessibility = false
    @Published private(set) var hasScreenCapture = false
    @Published var busy = false
    @Published private(set) var isRefreshing = false
    @Published var activity = ""
    @Published var message = String(localized: "Choose an app window to start creating screenshots.")
    @Published var messageIsError = false
    @Published var windowWidth = "1280"
    @Published var windowHeight = "800"
    @Published var windowSizing: WindowSizing = .current
    @Published var changePosition = false
    @Published var windowX = "0"
    @Published var windowY = "0"
    @Published var resizeResult: ResizeResult?
    @Published var capture: CapturedWindow?
    @Published var captureAppName = ""
    @Published var renderedPreview: CGImage?
    @Published var previewError: String?
    @Published var previewBusy = false
    @Published var originalSize = true
    @Published var exportWidth = "2560"
    @Published var exportHeight = "1600"
    @Published var resizeMode: ResizeMode = .fit
    @Published private(set) var exportReceipt: ExportReceipt?
    @Published private(set) var renderedConfiguration: ExportConfiguration?

    private let captureService: any WindowCapturing
    private let windowService: any WindowResizing
    private let images: any ImageProcessing
    private let runningApps: () -> [RunningApp]
    private let exportDestination: (String, PixelSize) async -> URL?
    private var previewTask: Task<Void, Never>?
    private var previewGeneration = UUID()
    private var renderedCaptureID: UUID?
    private var refreshTask: Task<Void, Never>?
    private var refreshPending = false
    private let permissions: PermissionMonitor
    private var permissionSubscription: AnyCancellable?

    init(permissions: PermissionMonitor? = nil,
         captureService: any WindowCapturing = WindowCaptureService(),
         windowService: any WindowResizing = AccessibilityWindowService(),
         images: any ImageProcessing = ImageProcessingService(),
         runningApps: (() -> [RunningApp])? = nil,
         exportDestination: ((String, PixelSize) async -> URL?)? = nil) {
        self.permissions = permissions ?? PermissionMonitor()
        self.captureService = captureService
        self.windowService = windowService
        self.images = images
        self.runningApps = runningApps ?? Self.readRunningApps
        self.exportDestination = exportDestination ?? Self.chooseExportDestination
        self.permissions.refresh()
        hasAccessibility = self.permissions.snapshot.accessibility
        hasScreenCapture = self.permissions.snapshot.screenCapture
        permissionSubscription = self.permissions.$snapshot.dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyPermissions() }
    }

    var selectedApp: RunningApp? { apps.first { $0.id == selectedAppID } }
    var appWindows: [WindowDescriptor] { windows.filter { $0.processID == selectedAppID } }
    var selectedWindow: WindowDescriptor? { appWindows.first { $0.id == selectedWindowID } }
    var canCapture: Bool { !busy && !isRefreshing && hasScreenCapture && selectedWindow != nil }
    var canResize: Bool { canCapture && hasAccessibility && windowValidationError == nil }
    var canPerformCapture: Bool { windowSizing == .current ? canCapture : canResize }
    var captureActionTitle: String {
        windowSizing == .current ? String(localized: "Capture") : String(localized: "Resize & Capture")
    }
    var windowValidationError: String? {
        guard windowSizing == .custom else { return nil }
        do { _ = try windowRequest(); return nil } catch { return error.localizedDescription }
    }
    var outputValidationError: String? {
        guard capture != nil, !originalSize else { return nil }
        do { _ = try PixelSize(widthText: exportWidth, heightText: exportHeight); return nil }
        catch { return error.localizedDescription }
    }
    var previewRequest: PreviewRequest {
        PreviewRequest(captureID: capture?.id, originalSize: originalSize,
                       width: exportWidth, height: exportHeight, mode: resizeMode)
    }
    var previewMatchesOutput: Bool {
        guard let capture, let config = exportConfiguration else { return false }
        return renderedPreview != nil && renderedCaptureID == capture.id && renderedConfiguration == config
    }
    var canExport: Bool { !busy && !previewBusy && previewError == nil && previewMatchesOutput }
    var isCurrentExported: Bool {
        guard let receipt = exportReceipt, let capture, let config = exportConfiguration else { return false }
        return receipt.captureID == capture.id && receipt.configuration == config
    }
    var lastExportURL: URL? { exportReceipt?.url }
    var previewIsFromEarlierWindowSize: Bool {
        guard let shot = capture, let window = selectedWindow else { return false }
        return !WindowMatcher.sameFrame(shot.window.frame, window.frame, tolerance: 0.5)
    }

    var exportConfiguration: ExportConfiguration? { try? configuration() }
    var isUpscaling: Bool {
        guard let source = capture?.image, let configuration = exportConfiguration else { return false }
        let rect = ImageExporter.destinationRect(source: CGSize(width: source.width, height: source.height),
                                                target: configuration.size.cgSize, mode: configuration.mode)
        return rect.width > CGFloat(source.width) + 0.5 || rect.height > CGFloat(source.height) + 0.5
    }

    func checkPermissions() {
        permissions.refresh()
    }

    private func applyPermissions() {
        let snapshot = permissions.snapshot
        let screenChanged = hasScreenCapture != snapshot.screenCapture
        if hasAccessibility != snapshot.accessibility { hasAccessibility = snapshot.accessibility }
        if screenChanged {
            hasScreenCapture = snapshot.screenCapture
            requestRefresh()
        }
    }

    func monitorPermissions() async {
        await permissions.monitor()
    }

    func requestAccessibility() {
        permissions.requestAccessibility()
    }

    func requestScreenCapture() {
        permissions.requestScreenCapture()
    }

    func openPrivacy(_ section: String) {
        permissions.watchForSettingsChanges()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Coalesce focus, app lifecycle, and permission changes without interrupting a capture/export.
    func requestRefresh() {
        refreshPending = true
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard let self, !busy, !isRefreshing else { return }
            await refresh(automatic: true)
        }
    }

    private static func readRunningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .map { RunningApp(id: $0.processIdentifier, name: $0.localizedName ?? String(localized: "App \(String($0.processIdentifier))"), icon: $0.icon) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func refresh(automatic: Bool = false) async {
        guard !busy, !isRefreshing else { refreshPending = true; return }
        refreshPending = false
        isRefreshing = true
        defer {
            isRefreshing = false
            if refreshPending { requestRefresh() }
        }
        checkPermissions()
        // Read the actual permission now, not the asynchronously delivered UI notification.
        if hasScreenCapture != permissions.snapshot.screenCapture { hasScreenCapture = permissions.snapshot.screenCapture }
        apps = runningApps()
        if let selectedAppID, !apps.contains(where: { $0.id == selectedAppID }) { invalidateTarget() }
        guard hasScreenCapture else {
            windows = []
            invalidateTarget(keepApp: true)
            if !automatic { status(String(localized: "Allow Screen Recording to choose a window.")) }
            return
        }
        do {
            windows = try await captureService.windows()
            if let selectedWindowID, !appWindows.contains(where: { $0.id == selectedWindowID }) {
                invalidateTarget(keepApp: true)
                status(String(localized: "The previously selected window is no longer available. Choose another window."))
            } else {
                if selectedWindowID == nil, appWindows.count == 1 {
                    selectWindow(appWindows.first?.id)
                }
                if !automatic { status(String(localized: "Window list updated.")) }
            }
        } catch {
            // A transient enumeration failure must not destroy an unexported capture.
            if !automatic { status(error.localizedDescription, error: true) }
        }
    }

    func selectApp(_ id: pid_t?) {
        guard !busy else { return }
        guard id != selectedAppID else { return }
        guard id == nil || apps.contains(where: { $0.id == id }) else { return }
        selectedAppID = id
        selectedWindowID = appWindows.count == 1 ? appWindows.first?.id : nil
        windowSelectionChanged()
    }

    func selectWindow(_ id: CGWindowID?) {
        guard !busy else { return }
        guard id != selectedWindowID else { return }
        guard id == nil || appWindows.contains(where: { $0.id == id }) else { return }
        selectedWindowID = id
        windowSelectionChanged()
    }

    /// Automatic loss of a target stops future captures but must not discard work.
    /// A new explicit selection still clears the single, temporary screenshot.
    private func invalidateTarget(keepApp: Bool = false) {
        if !keepApp, selectedAppID != nil { selectedAppID = nil }
        if selectedWindowID != nil { selectedWindowID = nil }
        resizeResult = nil
    }

    private func windowSelectionChanged() {
        clearCapture()
        resizeResult = nil
        guard let window = selectedWindow else { return }
        windowWidth = WindowDescriptor.number(window.frame.width)
        windowHeight = WindowDescriptor.number(window.frame.height)
        windowX = WindowDescriptor.number(window.frame.minX)
        windowY = WindowDescriptor.number(window.frame.minY)
        status(String(localized: "Selected “\(window.displayTitle)”. Use the capture button in the toolbar."))
    }

    func performCapture() async {
        checkPermissions()
        applyPermissions()
        guard canPerformCapture else { return }
        if windowSizing == .custom { await resize(andCapture: true) }
        else { await takeScreenshot() }
    }

    private func windowRequest() throws -> WindowRequest {
        let request = try WindowRequest(width: windowWidth, height: windowHeight,
                                        x: changePosition ? windowX : nil, y: changePosition ? windowY : nil)
        if let point = request.position { try validatePosition(point, size: request.size) }
        return request
    }

    func resize(andCapture: Bool) async {
        checkPermissions()
        applyPermissions()
        guard canResize, let selected = selectedWindow else { return }
        begin(andCapture ? String(localized: "Resizing, verifying, and capturing…") : String(localized: "Resizing and verifying the window…"))
        resizeResult = nil
        defer { end() }
        do {
            let request = try windowRequest()
            let current = try await captureService.current(selected)
            let result = try await windowService.resize(current, request: request)
            resizeResult = result
            replaceWindow(WindowDescriptor(id: current.id, processID: current.processID,
                                           title: current.title, frame: result.actualFrame))
            let actual = WindowDescriptor.describe(result.actualFrame.size)
            if andCapture {
                guard result.isStable else {
                    throw FrameKitError(String(localized: "The layout has not settled, so capture was skipped. Actual size: \(actual) pt. Try capturing again shortly.", bundle: AppLocalization.bundle))
                }
                let shot = try await captureService.capture(current, expectedFrame: result.actualFrame)
                accept(shot)
                status(result.isExact ? String(localized: "Size verified. Screenshot captured.")
                       : String(localized: "Captured at the actual size of \(actual) pt. The app limited the requested size or position."))
            } else {
                status(result.isExact ? String(localized: "Window resized. Actual size verified.")
                       : String(localized: "Partially applied. Actual size: \(actual) pt. Check the resize result."))
            }
        } catch { status(error.localizedDescription, error: true) }
    }

    func takeScreenshot() async {
        guard canCapture, let selected = selectedWindow else { return }
        begin(capture == nil ? String(localized: "Capturing the selected window…") : String(localized: "Retaking the screenshot…"))
        defer { end() }
        do {
            let shot = try await captureService.capture(selected, expectedFrame: nil)
            if let result = resizeResult, !WindowMatcher.sameFrame(result.actualFrame, shot.window.frame, tolerance: 0.5) {
                resizeResult = nil
            }
            accept(shot)
            status(String(localized: "Screenshot captured. The preview shows the export result."))
        } catch {
            status(capture == nil ? error.localizedDescription
                   : String(localized: "\(error.localizedDescription) The previous screenshot is still displayed."), error: true)
        }
    }

    private func accept(_ shot: CapturedWindow) {
        capture = shot
        captureAppName = selectedApp?.name ?? String(localized: "App")
        exportReceipt = nil
        renderedPreview = nil
        renderedConfiguration = nil
        renderedCaptureID = nil
        replaceWindow(shot.window)
        schedulePreview()
    }

    private func clearCapture() {
        previewTask?.cancel()
        previewGeneration = UUID()
        capture = nil
        renderedPreview = nil
        previewError = nil
        previewBusy = false
        exportReceipt = nil
        renderedConfiguration = nil
        renderedCaptureID = nil
    }

    private func replaceWindow(_ updated: WindowDescriptor) {
        if let index = windows.firstIndex(where: { $0.id == updated.id && $0.processID == updated.processID }) {
            windows[index] = updated
        }
    }

    private func validatePosition(_ point: CGPoint, size: CGSize) throws {
        let window = CGRect(origin: point, size: size)
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = NSScreen.screens.map { screen in
            let frame = screen.visibleFrame
            return CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
        }
        // Leave a useful part of the title bar reachable, including on displays with negative coordinates.
        let titleBar = CGRect(x: window.minX, y: window.minY, width: window.width, height: min(28, window.height))
        guard screens.contains(where: {
            let overlap = $0.intersection(titleBar)
            return overlap.width >= min(80, size.width) && overlap.height >= min(20, size.height)
        }) else { throw FrameKitError(String(localized: "This position would move the title bar offscreen. Choose a visible position.", bundle: AppLocalization.bundle)) }
    }

    private func configuration() throws -> ExportConfiguration {
        guard let source = capture?.image else { throw FrameKitError(String(localized: "Capture a window first.", bundle: AppLocalization.bundle)) }
        let size = try originalSize
            ? PixelSize(width: source.width, height: source.height)
            : PixelSize(widthText: exportWidth, heightText: exportHeight)
        return ExportConfiguration(size: size, mode: originalSize ? .fit : resizeMode)
    }

    func schedulePreview() {
        previewTask?.cancel()
        let generation = UUID()
        previewGeneration = generation
        previewError = nil
        previewBusy = false
        guard let source = capture?.image else { previewBusy = false; return }
        let captureID = capture?.id
        let config: ExportConfiguration
        // Keep the previous image while a field is empty or invalid; the field shows its own error.
        do { config = try configuration() } catch { return }
        if previewMatchesOutput { return }
        previewBusy = true
        previewTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
                let rendered = try await images.preview(source, configuration: config)
                guard !Task.isCancelled, previewGeneration == generation,
                      capture?.id == captureID, exportConfiguration == config else { return }
                renderedPreview = rendered
                renderedConfiguration = config
                renderedCaptureID = captureID
                previewBusy = false
            } catch {
                guard !Task.isCancelled, previewGeneration == generation else { return }
                previewError = error.localizedDescription
                previewBusy = false
            }
        }
    }

    func export() async {
        guard canExport, let shot = capture, let image = renderedPreview,
              let config = renderedConfiguration else { return }
        begin(String(localized: "Choose a save location…"))
        defer { end() }
        let safeName = captureAppName.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        let name = "\(safeName)-\(config.size.width)x\(config.size.height).png"
        guard let url = await exportDestination(name, config.size) else { return }
        activity = String(localized: "Exporting and verifying the file…")
        do {
            // Save exactly the rendered preview. Export never changes size or renders a new image.
            try await images.saveRendered(image, size: config.size, to: url)
            exportReceipt = ExportReceipt(captureID: shot.id, configuration: config, url: url)
            status(String(localized: "Saved \(url.lastPathComponent). Pixel dimensions and PNG format verified."))
        } catch { status(String(localized: "Export failed: \(error.localizedDescription)"), error: true) }
    }

    private static func chooseExportDestination(_ name: String, _ size: PixelSize) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = name
        panel.title = String(localized: "Export Screenshot")
        panel.message = String(localized: "\(size.label) · PNG · sRGB · No alpha channel")
        let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            } else { panel.begin { continuation.resume(returning: $0) } }
        }
        return response == .OK ? panel.url : nil
    }

    func showExport() { if let lastExportURL { NSWorkspace.shared.activateFileViewerSelecting([lastExportURL]) } }
    private func begin(_ text: String) { busy = true; activity = text }
    private func end() {
        busy = false
        activity = ""
        if refreshPending { requestRefresh() }
    }
    private func status(_ text: String, error: Bool = false) { message = text; messageIsError = error }
}
