import SwiftUI

struct PermissionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("系统权限").font(.headline)
            permissionRow("辅助功能", detail: "调整其他应用的窗口", granted: model.hasAccessibility,
                          request: model.requestAccessibility, settings: { model.openPrivacy("Privacy_Accessibility") })
            permissionRow("屏幕录制", detail: "读取窗口列表和截取画面", granted: model.hasScreenCapture,
                          request: model.requestScreenCapture, settings: { model.openPrivacy("Privacy_ScreenCapture") })
            if !model.hasAccessibility || !model.hasScreenCapture {
                Text("权限状态会自动更新。屏幕录制授权后点击刷新读取窗口；系统要求时重新打开应用。")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("已开启权限，但仍未识别？") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("旧记录可能属于之前的构建或另一个副本。请移除对应的旧记录，重新添加当前运行的应用并开启权限。")
                        Button("在 Finder 中显示当前应用", action: model.revealRunningApp)
                        Text(model.runningAppPath).textSelection(.enabled).foregroundStyle(.secondary)
                    }.font(.caption).padding(.top, 8)
                }.font(.caption)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20).frame(width: 360)
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool,
                               request: @escaping () -> Void, settings: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle" : "circle.dashed").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if granted {
                Text("已允许").font(.caption).foregroundStyle(.secondary)
            } else {
                Menu {
                    Button("请求授权", action: request)
                    Button("打开系统设置", action: settings)
                } label: { Text("授权") } primaryAction: { request() }
                .fixedSize().disabled(model.busy)
            }
        }
    }
}
