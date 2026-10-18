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
            CommandMenu("Capture") {
                Button("Refresh Window List") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command).disabled(model.busy)
                Button("Capture Selected Window") { Task { await model.takeScreenshot() } }
                    .keyboardShortcut("k", modifiers: .command).disabled(!model.canCapture)
                Button("Export PNG…") { Task { await model.export() } }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(model.capture == nil || model.busy || model.exportConfiguration == nil)
            }
        }
    }
}
