import AppKit

@MainActor
enum ApplicationRemoval {
    private static var confirming = Set<String>()

    static func permittedPath(_ url: URL, bundleID: String, ownBundleID: String,
                              applicationRoots: [URL]) -> Bool {
        ApplicationRemovalPolicy.permittedPath(url, bundleID: bundleID,
                                              ownBundleID: ownBundleID, applicationRoots: applicationRoots)
    }

    static func removableURL(for app: LaunchApp, store: LayoutStore) -> URL? {
        guard let url = store.resolvedURL(for: app)?.standardizedFileURL,
              url.resolvingSymlinksInPath().path == url.path,
              permittedPath(url, bundleID: app.bundleIdentifier,
                            ownBundleID: Bundle.main.bundleIdentifier ?? "local.ilaunchpad.app",
                            applicationRoots: ApplicationRemovalPolicy.applicationRoots),
              url != Bundle.main.bundleURL.standardizedFileURL,
              Bundle(url: url)?.bundleIdentifier == app.bundleIdentifier else { return nil }
        guard FileManager.default.isDeletableFile(atPath: url.path) else { return nil }
        return url
    }

    static func confirm(_ app: LaunchApp, store: LayoutStore, window: NSWindow?) {
        guard !store.isPreviewingDrag, let url = removableURL(for: app, store: store),
              let window, window.attachedSheet == nil,
              confirming.insert(app.id).inserted else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "将“\(app.name)”移到废纸篓？"
        alert.informativeText = "将 \(url.path) 移到废纸篓，并从 iLaunchPad 布局中移除。\n\n此操作只移动应用包，不会删除个人文稿、设置、缓存、共享容器或辅助文件，也不会取消订阅。清倒废纸篓前可以恢复。请先退出该应用。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "移到废纸篓")
        alert.beginSheetModal(for: window) { response in
            Task { @MainActor in
                defer { confirming.remove(app.id) }
                guard response == .alertSecondButtonReturn else { return }
                guard !store.isPreviewingDrag,
                      removableURL(for: app, store: store) == url else {
                    store.lastError = "应用位置、身份或删除权限已变化，未移到废纸篓。"
                    return
                }
                guard !NSWorkspace.shared.runningApplications.contains(where: {
                    $0.bundleURL?.standardizedFileURL == url || $0.bundleIdentifier == app.bundleIdentifier
                }) else {
                    store.lastError = "请先退出“\(app.name)”，再移到废纸篓。"
                    return
                }
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    store.removeUninstalledApplication(app)
                } catch {
                    store.lastError = "无法将“\(app.name)”移到废纸篓：\(error.localizedDescription)"
                }
            }
        }
    }
}
