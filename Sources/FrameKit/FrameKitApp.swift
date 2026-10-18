import AppKit
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
            CommandGroup(replacing: .appInfo) {
                Button("About FrameKit") { FrameKitAbout.show() }
            }
            SidebarCommands()
            InspectorPaneCommands()
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Capture") {
                Button("Refresh Window List") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command).disabled(model.busy || model.isRefreshing)
                Button(model.captureActionTitle) { Task { await model.performCapture() } }
                    .keyboardShortcut("k", modifiers: .command).disabled(!model.canPerformCapture)
                Button("Resize Only") { Task { await model.resize(andCapture: false) } }
                    .disabled(model.windowSizing != .custom || !model.canResize)
                Divider()
                Button("Export PNG…") { Task { await model.export() } }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(!model.canExport)
            }
        }
    }
}

@MainActor
private enum FrameKitAbout {
    static func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 3
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let credits = NSMutableAttributedString(
            string: String(localized: "Resize windows. Capture screenshots. Export PNGs.") + "\n\n",
            attributes: attributes
        )

        func appendLink(_ title: String, destination: String) {
            guard let url = URL(string: destination) else { return }
            var linkAttributes = attributes
            linkAttributes[.link] = url
            credits.append(NSAttributedString(string: title, attributes: linkAttributes))
        }

        appendLink("Gavin Schnee Studio", destination: "https://gavinschneestudio.org/")
        credits.append(NSAttributedString(string: "\n\n", attributes: attributes))
        appendLink(String(localized: "Website"), destination: "https://gavinschneestudio.org/products/framekit.html")
        credits.append(NSAttributedString(string: " · ", attributes: attributes))
        appendLink(String(localized: "Support"), destination: "https://gavinschneestudio.org/contact.html")
        credits.append(NSAttributedString(string: " · ", attributes: attributes))
        appendLink(String(localized: "Privacy Policy"), destination: "https://gavinschneestudio.org/privacy.html#framekit")

        // AppKit reads the icon, version, build number, and copyright from the bundle.
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
