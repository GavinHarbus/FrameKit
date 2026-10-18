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
    @Published var selectedAppID: pid_t?
    @Published var selectedWindowID: CGWindowID?
    @Published private(set) var hasAccessibility = false
    @Published private(set) var hasScreenCapture = false
    @Published var busy = false
    @Published var activity = ""
    @Published var message = "选择应用窗口，开始制作截图。"
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
    private let permissions = PermissionMonitor()
    private var permissionSubscription: AnyCancellable?

    init() {
        permissionSubscription = permissions.$snapshot.sink { [weak self] snapshot in
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
        begin("正在读取应用与窗口…")
        defer { end() }
        checkPermissions()
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .map { RunningApp(id: $0.processIdentifier, name: $0.localizedName ?? "应用 \($0.processIdentifier)", icon: $0.icon) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let selectedAppID, !apps.contains(where: { $0.id == selectedAppID }) {
            self.selectedAppID = nil
            selectedWindowID = nil
            clearCapture()
        }
        guard hasScreenCapture else {
            windows = []
            selectedWindowID = nil
            status("允许屏幕录制后，点击刷新即可选择窗口。")
            return
        }
        do {
            windows = try await captureService.windows()
            if let selectedWindowID, !appWindows.contains(where: { $0.id == selectedWindowID }) {
                self.selectedWindowID = nil
                clearCapture()
                status("之前选择的窗口已不可用，请重新选择。")
            } else {
                if selectedWindowID == nil, appWindows.count == 1 {
                    selectedWindowID = appWindows.first?.id
                    windowSelectionChanged()
                }
                status("窗口列表已更新。")
            }
        } catch { windows = []; status(error.localizedDescription, error: true) }
    }

    func appSelectionChanged() {
        selectedWindowID = appWindows.count == 1 ? appWindows.first?.id : nil
        windowSelectionChanged()
    }

    func windowSelectionChanged() {
        clearCapture()
        resizeResult = nil
        guard let window = selectedWindow else { return }
        windowWidth = WindowDescriptor.number(window.frame.width)
        windowHeight = WindowDescriptor.number(window.frame.height)
        windowX = WindowDescriptor.number(window.frame.minX)
        windowY = WindowDescriptor.number(window.frame.minY)
        status("已选择「\(window.displayTitle)」，可调整尺寸或直接截图。")
    }

    func resize(andCapture: Bool) async {
        checkPermissions()
        guard canResize, let selected = selectedWindow else { return }
        begin(andCapture ? "正在调整、验证并截图…" : "正在调整并验证窗口…")
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
                    throw FrameKitError("窗口布局尚未稳定，未自动截图。实际读取：\(actual) pt。请稍后直接截图。")
                }
                let shot = try await captureService.capture(current, expectedFrame: result.actualFrame)
                accept(shot)
                status(result.isExact ? "尺寸已验证，截图完成。" : "已按实际尺寸 \(actual) pt 截图；目标应用限制了请求的尺寸或位置。")
            } else {
                status(result.isExact ? "窗口已调整，实际尺寸验证通过。" : "请求未完全生效。实际尺寸 \(actual) pt，请查看验证结果。")
            }
        } catch { status(error.localizedDescription, error: true) }
    }

    func takeScreenshot() async {
        guard canCapture, let selected = selectedWindow else { return }
        begin(capture == nil ? "正在截取所选窗口…" : "正在重新截取窗口…")
        defer { end() }
        do {
            let shot = try await captureService.capture(selected)
            if let result = resizeResult, !WindowMatcher.sameFrame(result.actualFrame, shot.window.frame, tolerance: 0.5) {
                resizeResult = nil
            }
            accept(shot)
            status("截图完成，预览为最终导出效果。")
        } catch {
            status(error.localizedDescription + (capture == nil ? "" : " 当前仍显示上一次截图。"), error: true)
        }
    }

    private func accept(_ shot: CapturedWindow) {
        capture = shot
        captureAppName = selectedApp?.name ?? "应用"
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
        }) else { throw FrameKitError("这个坐标会把窗口标题栏移出可用屏幕，请选择可见的位置。") }
    }

    private func configuration() throws -> ExportConfiguration {
        guard let source = capture?.image else { throw FrameKitError("请先截取窗口。") }
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
        begin("选择保存位置…")
        defer { end() }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        let safeName = captureAppName.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        panel.nameFieldStringValue = "\(safeName)-\(config.size.width)x\(config.size.height).png"
        panel.title = "导出截图"
        panel.message = "\(config.size.label) · PNG · sRGB · 不含透明通道"
        let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            } else { panel.begin { continuation.resume(returning: $0) } }
        }
        guard response == .OK, let url = panel.url else { return }
        activity = "正在导出并校验文件…"
        do {
            try await images.save(shot.image, configuration: config, to: url)
            lastExportURL = url
            status("已保存 \(url.lastPathComponent)，像素尺寸和 PNG 格式校验通过。")
        } catch { status("导出失败：" + error.localizedDescription, error: true) }
    }

    func showExport() { if let lastExportURL { NSWorkspace.shared.activateFileViewerSelecting([lastExportURL]) } }
    func revealRunningApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
    var runningAppPath: String { Bundle.main.bundleURL.path }
    private func begin(_ text: String) { busy = true; activity = text }
    private func end() { busy = false; activity = "" }
    private func status(_ text: String, error: Bool = false) { message = text; messageIsError = error }
}
