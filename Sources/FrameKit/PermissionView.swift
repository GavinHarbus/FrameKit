import SwiftUI

struct PermissionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Permissions").font(.headline)
            permissionRow("Accessibility", detail: "Resize and move other apps’ windows", granted: model.hasAccessibility,
                          request: model.requestAccessibility, settings: { model.openPrivacy("Privacy_Accessibility") })
            permissionRow("Screen Recording", detail: "List windows and capture screenshots", granted: model.hasScreenCapture,
                          request: model.requestScreenCapture, settings: { model.openPrivacy("Privacy_ScreenCapture") })
            if !model.hasAccessibility || !model.hasScreenCapture {
                Text("Permissions and windows update automatically after you allow access. Reopen FrameKit if macOS asks.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20).frame(width: 360)
    }

    private func permissionRow(_ title: LocalizedStringKey, detail: LocalizedStringKey, granted: Bool,
                               request: @escaping () -> Void, settings: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle" : "circle.dashed").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if granted {
                Text("Allowed").font(.caption).foregroundStyle(.secondary)
            } else {
                Menu {
                    Button("Request Access", action: request)
                    Button("Open System Settings", action: settings)
                } label: { Text("Allow Access") } primaryAction: { request() }
                .fixedSize().disabled(model.busy)
            }
        }
    }
}
