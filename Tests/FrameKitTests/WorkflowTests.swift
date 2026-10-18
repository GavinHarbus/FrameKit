import CoreGraphics
import Foundation
import XCTest
import FrameKitCore

private actor WorkflowWindows: WindowCapturing, WindowResizing {
    var available = [WindowDescriptor(id: 10, processID: 100, title: "Demo", frame: CGRect(x: 20, y: 40, width: 800, height: 600))]
    var captures = 0
    var resizes = 0
    var queries = 0
    var failEnumeration = false
    let image: CGImage

    init() {
        let context = CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        image = context.makeImage()!
    }
    func windows() async throws -> [WindowDescriptor] {
        queries += 1
        if failEnumeration { throw FrameKitError("Temporary failure") }
        return available
    }
    func current(_ selected: WindowDescriptor) async throws -> WindowDescriptor { available.first { $0.id == selected.id }! }
    func capture(_ selected: WindowDescriptor, expectedFrame: CGRect?) async throws -> CapturedWindow {
        let window = available.first { $0.id == selected.id }!
        if let expectedFrame, expectedFrame != window.frame { throw FrameKitError("Incorrect target geometry") }
        captures += 1
        return CapturedWindow(image: image, window: window, scale: 1)
    }
    func resize(_ selected: WindowDescriptor, request: WindowRequest) async throws -> ResizeResult {
        resizes += 1
        let frame = CGRect(origin: request.position ?? selected.frame.origin, size: request.size)
        available = [WindowDescriptor(id: selected.id, processID: selected.processID, title: selected.title, frame: frame)]
        return ResizeResult(requested: request, actualFrame: frame, isStable: true)
    }
    func removeWindows() { available = [] }
    func setTitle(_ title: String) {
        available = available.map { WindowDescriptor(id: $0.id, processID: $0.processID, title: title, frame: $0.frame) }
    }
    func setFailure() { failEnumeration = true }
    func counts() -> (Int, Int, Int) { (captures, resizes, queries) }
}

private actor WorkflowImages: ImageProcessing {
    var previewCount = 0
    var savedImage: CGImage?
    var waiting: [Int: CheckedContinuation<Void, Never>] = [:]
    let suspendWidths: Set<Int>
    init(suspendWidths: Set<Int> = []) { self.suspendWidths = suspendWidths }

    func preview(_ source: CGImage, configuration: ExportConfiguration) async throws -> CGImage {
        previewCount += 1
        if suspendWidths.contains(configuration.size.width) {
            // Deliberately ignore cancellation to exercise the generation/configuration guards.
            await withCheckedContinuation { waiting[configuration.size.width] = $0 }
        }
        return try ImageExporter.render(source, configuration: configuration)
    }
    func saveRendered(_ image: CGImage, size: PixelSize, to url: URL) async throws {
        savedImage = image
        try ImageExporter.pngData(image, expected: size).write(to: url)
    }
    func isWaiting(_ width: Int) -> Bool { waiting[width] != nil }
    func release(_ width: Int) { waiting.removeValue(forKey: width)?.resume() }
    func summary() -> (Int, CGImage?) { (previewCount, savedImage) }
}

final class WorkflowTests: XCTestCase {
    @MainActor
    private func makeModel(accessibility: Bool = false, windows: WorkflowWindows = WorkflowWindows(),
                           images: WorkflowImages = WorkflowImages(), destination: URL? = nil,
                           onExportName: ((String) -> Void)? = nil) async throws -> AppModel {
        let permissions = PermissionMonitor(read: { PermissionSnapshot(accessibility: accessibility, screenCapture: true) },
                                            requestAccessibility: {}, requestScreenCapture: {})
        let model = AppModel(permissions: permissions, captureService: windows, windowService: windows, images: images,
                             runningApps: { [RunningApp(id: 100, name: "Demo", icon: nil)] },
                             exportDestination: { name, _ in onExportName?(name); return destination })
        await model.refresh()
        model.selectApp(100)
        return model
    }

    @MainActor
    private func waitFor(_ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(3)
        while !(await condition()), Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        let fulfilled = await condition()
        XCTAssertTrue(fulfilled, "Workflow did not reach expected state", file: file, line: line)
    }

    @MainActor
    func testCurrentSizeCapturesWithoutAccessibilityOrResizing() async throws {
        let windows = WorkflowWindows()
        let model = try await makeModel(windows: windows)
        XCTAssertEqual(model.windowSizing, .current)
        XCTAssertTrue(model.canPerformCapture)
        model.windowWidth = "invalid unused custom input"
        await model.performCapture()
        await waitFor { model.previewMatchesOutput }
        let counts = await windows.counts()
        XCTAssertEqual(counts.0, 1)
        XCTAssertEqual(counts.1, 0)
        XCTAssertEqual(model.renderedConfiguration?.size, try PixelSize(width: 80, height: 40))
        XCTAssertTrue(model.canExport)
    }

    @MainActor
    func testCustomModeRequiresPermissionAndValidDimensions() async throws {
        let windows = WorkflowWindows()
        let model = try await makeModel(windows: windows)
        model.windowSizing = .custom
        XCTAssertFalse(model.canPerformCapture)
        await model.performCapture()
        let counts = await windows.counts()
        XCTAssertEqual(counts.0, 0)
        XCTAssertEqual(counts.1, 0)

        let allowed = try await makeModel(accessibility: true, windows: windows)
        allowed.windowSizing = .custom
        allowed.windowWidth = ""
        XCTAssertNotNil(allowed.windowValidationError)
        XCTAssertFalse(allowed.canPerformCapture)
        await allowed.performCapture()
        let after = await windows.counts()
        XCTAssertEqual(after.1, 0)
    }

    @MainActor
    func testRetakeAppliesLatestCustomWindowDimensions() async throws {
        let windows = WorkflowWindows()
        let model = try await makeModel(accessibility: true, windows: windows)
        model.windowSizing = .custom
        model.windowWidth = "640"
        model.windowHeight = "400"
        await model.performCapture()
        XCTAssertEqual(model.capture?.window.frame.size, CGSize(width: 640, height: 400))
        model.windowWidth = "1000"
        await model.performCapture()
        XCTAssertEqual(model.capture?.window.frame.width, 1000)
        let counts = await windows.counts()
        XCTAssertEqual(counts.0, 2)
        XCTAssertEqual(counts.1, 2)
    }

    @MainActor
    func testInvalidOutputKeepsPreviewAndBlocksExportUntilNewPreviewIsReady() async throws {
        let model = try await makeModel()
        await model.performCapture()
        await waitFor { model.canExport }
        let original = try XCTUnwrap(model.renderedPreview)
        model.originalSize = false
        model.exportWidth = ""
        model.schedulePreview()
        XCTAssertTrue(model.renderedPreview === original)
        XCTAssertNotNil(model.outputValidationError)
        XCTAssertNil(model.previewError)
        XCTAssertFalse(model.canExport)
        model.exportWidth = "40"
        model.exportHeight = "20"
        model.schedulePreview()
        XCTAssertTrue(model.renderedPreview === original)
        XCTAssertFalse(model.canExport)
        await waitFor { model.canExport }
        XCTAssertEqual(model.renderedPreview?.width, 40)
        XCTAssertEqual(model.renderedPreview?.height, 20)
    }

    @MainActor
    func testExportWritesDisplayedPixelsAndTracksWhichSettingsWereSaved() async throws {
        let images = WorkflowImages()
        let windows = WorkflowWindows()
        await windows.setTitle("Settings/偏好:General")
        var suggestedName: String?
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let model = try await makeModel(windows: windows, images: images, destination: url,
                                        onExportName: { suggestedName = $0 })
        await model.performCapture()
        await waitFor { model.canExport }
        let preview = try XCTUnwrap(model.renderedPreview)
        let before = await images.summary()
        await windows.setTitle("Another Page")
        await model.refresh(automatic: true)
        XCTAssertFalse(model.isCurrentExported)
        await model.export()
        XCTAssertEqual(suggestedName, "Demo-Settings-偏好-General-80x40.png",
                       "The filename must use the captured page title, sanitize path separators, and preserve Unicode.")
        let after = await images.summary()
        XCTAssertEqual(after.0, before.0, "Export must not perform a second resize/render.")
        XCTAssertTrue(after.1 === preview, "The exported bitmap must be the displayed preview.")
        try ImageExporter.validatePNG(Data(contentsOf: url), expected: PixelSize(width: 80, height: 40))
        XCTAssertTrue(model.isCurrentExported)
        model.originalSize = false
        XCTAssertFalse(model.isCurrentExported)
        model.originalSize = true
        XCTAssertTrue(model.isCurrentExported, "Returning to the exact saved output is still exported.")
        await model.performCapture()
        XCTAssertFalse(model.isCurrentExported, "A new capture always needs a new export.")
    }

    @MainActor
    func testCancelExportDoesNotMarkScreenshotAsSaved() async throws {
        let images = WorkflowImages()
        let model = try await makeModel(images: images)
        await model.performCapture()
        await waitFor { model.canExport }
        await model.export()
        XCTAssertFalse(model.isCurrentExported)
        XCTAssertNil(model.lastExportURL)
        let summary = await images.summary()
        XCTAssertNil(summary.1)
    }

    @MainActor
    func testAutoRefreshPreservesEditsAndCaptureEvenIfTargetDisappears() async throws {
        let windows = WorkflowWindows()
        let model = try await makeModel(windows: windows)
        await model.performCapture()
        await waitFor { model.canExport }
        let captureID = model.capture?.id
        model.windowSizing = .custom
        model.windowWidth = "1440"
        await model.refresh(automatic: true)
        XCTAssertEqual(model.selectedWindowID, 10)
        XCTAssertEqual(model.windowWidth, "1440")
        XCTAssertEqual(model.capture?.id, captureID)
        await windows.setFailure()
        await model.refresh(automatic: true)
        XCTAssertEqual(model.capture?.id, captureID)
        // A successful empty list invalidates the target, but the screenshot stays exportable.
        let disappearing = WorkflowWindows()
        let second = try await makeModel(windows: disappearing)
        await second.performCapture()
        await waitFor { second.canExport }
        await disappearing.removeWindows()
        await second.refresh(automatic: true)
        XCTAssertNil(second.selectedWindowID)
        XCTAssertNotNil(second.capture)
        XCTAssertFalse(second.canCapture)
        XCTAssertTrue(second.canExport)
    }

    @MainActor
    func testPermissionGrantAutomaticallyLoadsWindowsWithoutManualRefresh() async throws {
        var granted = false
        let permissions = PermissionMonitor(read: { PermissionSnapshot(accessibility: false, screenCapture: granted) },
                                            requestAccessibility: {}, requestScreenCapture: {})
        let windows = WorkflowWindows()
        let model = AppModel(permissions: permissions, captureService: windows,
                             runningApps: { [RunningApp(id: 100, name: "Demo", icon: nil)] })
        await model.refresh()
        model.selectApp(100)
        XCTAssertTrue(model.windows.isEmpty)
        granted = true
        model.checkPermissions()
        await waitFor { model.selectedWindowID == 10 }
        XCTAssertTrue(model.canPerformCapture)
    }

    @MainActor
    func testLatePreviewCannotReplaceNewerOutput() async throws {
        let images = WorkflowImages(suspendWidths: [40, 60])
        let model = try await makeModel(images: images)
        await model.performCapture()
        await waitFor { model.canExport }
        model.originalSize = false
        model.exportWidth = "40"
        model.exportHeight = "20"
        model.schedulePreview()
        await waitFor { await images.isWaiting(40) }
        model.exportWidth = "60"
        model.schedulePreview()
        await waitFor { await images.isWaiting(60) }
        await images.release(60)
        await waitFor { model.canExport }
        XCTAssertEqual(model.renderedPreview?.width, 60)
        await images.release(40)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.renderedPreview?.width, 60)
        XCTAssertTrue(model.previewMatchesOutput)
    }
}
