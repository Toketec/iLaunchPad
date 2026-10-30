import SwiftUI

struct LaunchpadSettingsView: View {
    @ObservedObject private var loginItem = LoginItemController.shared
    @AppStorage("iconScale") private var iconScale = 1.0
    @AppStorage("wallpaperBlur") private var wallpaperBlur = 24.0
    @AppStorage("showNames") private var showNames = true
    @AppStorage("returnToFirstPage") private var returnToFirstPage = true

    var body: some View {
        TabView {
            Form {
                Section("布局") {
                    LabeledContent("图标大小") {
                        HStack(spacing: 12) {
                            Image(systemName: "square.grid.3x3")
                            Slider(value: $iconScale, in: 0.75...1.15, step: 0.05)
                                .frame(width: 185)
                            Image(systemName: "square.grid.2x2")
                        }
                    }
                    Toggle("显示应用名称", isOn: $showNames)
                }
                Section("背景") {
                    Picker("壁纸模糊", selection: $wallpaperBlur) {
                        Text("轻柔").tag(12.0)
                        Text("标准").tag(24.0)
                        Text("柔和").tag(42.0)
                    }
                    .pickerStyle(.segmented)
                    Text("使用当前屏幕的桌面壁纸。搜索栏、页码和文件夹使用系统液态玻璃材质。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("外观", systemImage: "paintpalette") }


            Form {
                Section("打开与浏览") {
                    LabeledContent("显示 / 隐藏", value: "⌥ 空格 · F4")
                    LabeledContent("切换页面", value: "双指滑动 · ⌘ ← / →")
                    LabeledContent("选择应用", value: "方向键")
                    LabeledContent("打开应用", value: "回车")
                    Toggle("每次打开时回到第一页", isOn: $returnToFirstPage)
                }
                Section("辅助功能") {
                    Text("动画遵循系统的“减少动态效果”设置。搜索支持应用名称、拼音和拼音首字母。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("随系统启动") {
                    Toggle("登录时启动", isOn: Binding(get: { loginItem.isEnabled }, set: { enabled in
                        Task { await loginItem.setEnabled(enabled) }
                    }))
                    .disabled(loginItem.isUpdating)
                    Text("登录后在后台待命，不自动打开启动台。")
                        .font(.callout).foregroundStyle(.secondary)
                    if loginItem.status == .requiresApproval {
                        Text("需要在系统设置中允许").foregroundStyle(.secondary)
                        Button("打开登录项设置") { loginItem.openSystemSettings() }
                    }
                    if loginItem.status == .notFound {
                        Text("系统尚未识别此应用的登录服务。如开启失败，错误信息将显示在这里。")
                            .foregroundStyle(.secondary)
                    }
                    if let error = loginItem.errorMessage {
                        Text(error).foregroundStyle(.red).font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("交互", systemImage: "hand.draw") }
        }
        .padding(12)
        .frame(width: 510, height: 480)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }
}
