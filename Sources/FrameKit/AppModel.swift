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

@MainActor
final class AppModel: ObservableObject {
    @Published var apps: [RunningApp] = []
    @Published var windows: [WindowDescriptor] = []
    @Published private(set) var selectedAppID: pid_t?
    @Published private(set) var selectedWindowID: CGWindowID?
    @Published private(set) var hasAccessibility = false
    @Published private(set) var hasScreenCapture = false
    @Published var busy = false
    @Published var activity = ""
    @Published var message = String(localized: "Choose an app window to start creating screenshots.")
    @Published var messageIsError = false
    @Published var windowWidth = "1280"
    @Published var windowHeight = "800"
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
    @Published var lastExportURL: URL?

    private let captureService = WindowCaptureService()
    private let windowService = AccessibilityWindowService()
    private let images = ImageProcessingService()
    private var previewTask: Task<Void, Never>?
    private var previewGeneration = UUID()
    private let permissions: PermissionMonitor
    private var permissionSubscription: AnyCancellable?

    init(permissions: PermissionMonitor? = nil) {
        self.permissions = permissions ?? PermissionMonitor()
        permissionSubscription = self.permissions.$snapshot.sink { [weak self] snapshot in
            guard let self else { return }
            hasAccessibility = snapshot.accessibility
            hasScreenCapture = snapshot.screenCapture
        }
        checkPermissions()
    }

    var selectedApp: RunningApp? { apps.first { $0.id == selectedAppID } }
    var appWindows: [WindowDescriptor] { windows.filter { $0.processID == selectedAppID } }
    var selectedWindow: WindowDescriptor? { appWindows.first { $0.id == selectedWindowID } }
    var canCapture: Bool { !busy && hasScreenCapture && selectedWindow != nil }
    var canResize: Bool { canCapture && hasAccessibility }
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

    func refresh() async {
        guard !busy else { return }
        begin(String(localized: "Loading apps and windows…"))
        defer { end() }
        checkPermissions()
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .map { RunningApp(id: $0.processIdentifier, name: $0.localizedName ?? String(localized: "App \(String($0.processIdentifier))"), icon: $0.icon) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let selectedAppID, !apps.contains(where: { $0.id == selectedAppID }) {
            selectApp(nil)
        }
        guard hasScreenCapture else {
            windows = []
            selectWindow(nil)
            status(String(localized: "Allow Screen Recording, then refresh to choose a window."))
            return
        }
        do {
            windows = try await captureService.windows()
            if let selectedWindowID, !appWindows.contains(where: { $0.id == selectedWindowID }) {
                selectWindow(nil)
                status(String(localized: "The previously selected window is no longer available. Choose another window."))
            } else {
                if selectedWindowID == nil, appWindows.count == 1 {
                    selectWindow(appWindows.first?.id)
                }
                status(String(localized: "Window list updated."))
            }
        } catch { windows = []; status(error.localizedDescription, error: true) }
    }

    func selectApp(_ id: pid_t?) {
        guard id != selectedAppID else { return }
        guard id == nil || apps.contains(where: { $0.id == id }) else { return }
        selectedAppID = id
        selectedWindowID = appWindows.count == 1 ? appWindows.first?.id : nil
        windowSelectionChanged()
    }

    func selectWindow(_ id: CGWindowID?) {
        guard id != selectedWindowID else { return }
        guard id == nil || appWindows.contains(where: { $0.id == id }) else { return }
        selectedWindowID = id
        windowSelectionChanged()
    }

    private func windowSelectionChanged() {
        clearCapture()
        resizeResult = nil
        guard let window = selectedWindow else { return }
        windowWidth = WindowDescriptor.number(window.frame.width)
        windowHeight = WindowDescriptor.number(window.frame.height)
        windowX = WindowDescriptor.number(window.frame.minX)
        windowY = WindowDescriptor.number(window.frame.minY)
        status(String(localized: "Selected “\(window.displayTitle)”. Resize it or capture directly."))
    }

    func resize(andCapture: Bool) async {
        checkPermissions()
        guard canResize, let selected = selectedWindow else { return }
        begin(andCapture ? String(localized: "Resizing, verifying, and capturing…") : String(localized: "Resizing and verifying the window…"))
        resizeResult = nil
        defer { end() }
        do {
            let request = try WindowRequest(width: windowWidth, height: windowHeight,
                                            x: changePosition ? windowX : nil, y: changePosition ? windowY : nil)
            if let point = request.position { try validatePosition(point, size: request.size) }
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
            let shot = try await captureService.capture(selected)
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
        lastExportURL = nil
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
        lastExportURL = nil
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
        renderedPreview = nil
        previewError = nil
        guard let source = capture?.image else { previewBusy = false; return }
        let config: ExportConfiguration
        do { config = try configuration() } catch { previewError = error.localizedDescription; previewBusy = false; return }
        previewBusy = true
        previewTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
                let rendered = try await images.preview(source, configuration: config)
                guard !Task.isCancelled, previewGeneration == generation else { return }
                renderedPreview = rendered
                previewBusy = false
            } catch {
                guard !Task.isCancelled, previewGeneration == generation else { return }
                previewError = error.localizedDescription
                previewBusy = false
            }
        }
    }

    func export() async {
        guard !busy, let shot = capture else { return }
        let config: ExportConfiguration
        do { config = try configuration() } catch { status(error.localizedDescription, error: true); return }
        begin(String(localized: "Choose a save location…"))
        defer { end() }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        let safeName = captureAppName.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        panel.nameFieldStringValue = "\(safeName)-\(config.size.width)x\(config.size.height).png"
        panel.title = String(localized: "Export Screenshot")
        panel.message = String(localized: "\(config.size.label) · PNG · sRGB · No alpha channel")
        let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            } else { panel.begin { continuation.resume(returning: $0) } }
        }
        guard response == .OK, let url = panel.url else { return }
        activity = String(localized: "Exporting and verifying the file…")
        do {
            try await images.save(shot.image, configuration: config, to: url)
            lastExportURL = url
            status(String(localized: "Saved \(url.lastPathComponent). Pixel dimensions and PNG format verified."))
        } catch { status(String(localized: "Export failed: \(error.localizedDescription)"), error: true) }
    }

    func showExport() { if let lastExportURL { NSWorkspace.shared.activateFileViewerSelecting([lastExportURL]) } }
    private func begin(_ text: String) { busy = true; activity = text }
    private func end() { busy = false; activity = "" }
    private func status(_ text: String, error: Bool = false) { message = text; messageIsError = error }
}
