import AppKit
import SwiftUI

struct LaunchpadSettingsView: View {
    @ObservedObject private var loginItem = LoginItemController.shared
    @ObservedObject private var layoutStore = LayoutStore.shared
    @AppStorage("iconScale") private var iconScale = 1.0
    @AppStorage("wallpaperBlur") private var wallpaperBlur = 24.0
    @AppStorage("showNames") private var showNames = true
    @AppStorage("returnToFirstPage") private var returnToFirstPage = true
    @AppStorage("appIconStyle") private var appIconStyle = AppIconCatalog.defaultID

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
                Section("Apple 默认布局") {
                    LabeledContent {
                        Button("恢复…") { restoreAppleDefaultLayout() }
                            .disabled(layoutStore.isRestoringLayout)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Apple 默认布局")
                            Text("常用系统应用优先，实用工具归入“其他”，其余应用顺延。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("自定义布局备份（\(layoutStore.layoutBackups.count)/3）") {
                    if layoutStore.layoutBackups.isEmpty {
                        Text("还没有自定义布局备份")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(layoutStore.layoutBackups) { backup in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(backup.name)
                                    Text(backup.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("切换") { restoreBackup(backup) }
                                    .disabled(layoutStore.isRestoringLayout)
                                Menu {
                                    Button("用当前布局覆盖…") { overwriteBackup(backup) }
                                    Button("重命名…") { renameBackup(backup) }
                                    Divider()
                                    Button("删除…", role: .destructive) { deleteBackup(backup) }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .menuStyle(.borderlessButton)
                                .disabled(layoutStore.isRestoringLayout)
                            }
                        }
                    }
                    Button("备份当前布局…", systemImage: "plus") { createBackup() }
                        .disabled(!layoutStore.canCreateLayoutBackup)
                    if layoutStore.layoutBackups.count >= LayoutBackupRepository.maximumCount {
                        Text("已达到 3 份自定义布局上限。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if layoutStore.isRestoringLayout {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("正在核对已安装应用并切换布局…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("布局", systemImage: "square.grid.3x3") }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("选择你的火箭").font(.title2.bold())
                    Text("用于 Dock、访达与应用切换器，选择后即时生效，退出后仍会保留。")
                        .font(.callout).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 20) {
                        ForEach(AppIconCatalog.choices) { choice in
                            Button {
                                appIconStyle = choice.id
                                AppIconCatalog.apply(choice.id)
                            } label: {
                                VStack(spacing: 7) {
                                    if let image = AppIconCatalog.image(for: choice.id) {
                                        Image(nsImage: image).resizable().scaledToFit().frame(width: 70, height: 70)
                                    }
                                    Text(choice.name).font(.caption)
                                    Image(systemName: appIconStyle == choice.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(appIconStyle == choice.id ? Color.accentColor : Color.secondary)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.name)
                            .accessibilityValue(appIconStyle == choice.id ? "已选择" : "未选择")
                        }
                    }
                }
                .padding(20)
            }
            .tabItem { Label("应用图标", systemImage: "app.badge") }

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
        .onAppear {
            loginItem.refresh()
            appIconStyle = AppIconCatalog.normalizedID(appIconStyle)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }

    private func createBackup() {
        guard let name = promptForName(title: "备份当前布局", message: "为这份布局输入名称：",
                                       defaultValue: "布局 \(layoutStore.layoutBackups.count + 1)") else { return }
        layoutStore.createLayoutBackup(named: name)
    }

    private func renameBackup(_ backup: LayoutBackupSummary) {
        guard let name = promptForName(title: "重命名布局", message: "输入新的布局名称：",
                                       defaultValue: backup.name) else { return }
        layoutStore.renameLayoutBackup(id: backup.id, name: name)
    }

    private func overwriteBackup(_ backup: LayoutBackupSummary) {
        guard confirm(title: "覆盖“\(backup.name)”？",
                      message: "将用当前启动台布局替换这份备份。此操作无法撤销。",
                      action: "覆盖") else { return }
        layoutStore.overwriteLayoutBackup(id: backup.id)
    }

    private func restoreBackup(_ backup: LayoutBackupSummary) {
        guard confirm(title: "切换到“\(backup.name)”？",
                      message: "当前布局将被这份备份替换。尚未备份的整理结果会丢失。",
                      action: "切换") else { return }
        layoutStore.restoreLayoutBackup(id: backup.id)
    }

    private func deleteBackup(_ backup: LayoutBackupSummary) {
        guard confirm(title: "删除“\(backup.name)”？",
                      message: "只删除这份布局备份，不改变当前启动台布局。",
                      action: "删除") else { return }
        layoutStore.deleteLayoutBackup(id: backup.id)
    }

    private func restoreAppleDefaultLayout() {
        guard confirm(title: "恢复 Apple 默认布局？",
                      message: "当前布局将被重新初始化。建议先备份当前布局；已有自定义备份不会被删除。",
                      action: "恢复") else { return }
        layoutStore.restoreAppleDefaultLayout()
    }

    private func promptForName(title: String, message: String, defaultValue: String) -> String? {
        let field = NSTextField(string: defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private func confirm(title: String, message: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
