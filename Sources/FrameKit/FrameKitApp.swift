import SwiftUI

@main
struct FrameKitApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("FrameKit", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 1000, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            InspectorCommands()
            CommandGroup(replacing: .newItem) {}
            CommandMenu("截图") {
                Button("刷新窗口列表") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command).disabled(model.busy)
                Button("截取所选窗口") { Task { await model.takeScreenshot() } }
                    .keyboardShortcut("k", modifiers: .command).disabled(!model.canCapture)
                Button("导出 PNG…") { Task { await model.export() } }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(model.capture == nil || model.busy || model.exportConfiguration == nil)
            }
        }
    }
}
