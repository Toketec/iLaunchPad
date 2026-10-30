import AppKit
import Foundation

@MainActor
final class LayoutStore: ObservableObject {
    @Published private(set) var layout: LaunchLayout
    @Published var lastError: String?
    @Published var isEditing = false
    private var dragSnapshot: LaunchLayout?
    private var scanTask: Task<Void, Never>?
    private var directoryMonitor: ApplicationDirectoryMonitor?
    private var scanInProgress = false
    private var lastScanStarted = Date.distantPast
    private(set) var scanGeneration = UUID()
    private var deferredScan: [LaunchApp]?
    var isPreviewingDrag: Bool { dragSnapshot != nil }
    // Keep the native drag source alive when its folder closes mid-gesture.
    var dragLifetime: AnyObject?
    var dragOpenFolderID: String?
    var dragCurrentPage = 0
    var dragRoutingPausedUntil: TimeInterval = 0
    var dragDestination: DragDestination?
    var dragSessionID = UUID()
    private var dragAppearance: (sessionID: UUID, appID: String, crossedContainer: Bool)?
    private struct MergePreview {
        let sessionID: UUID
        let folderID: String
        let before: LaunchLayout
        let sourceFrame: CGRect
    }
    struct FolderNamingRequest: Equatable {
        let sessionID: UUID
        let folderID: String
    }
    private var mergePreview: MergePreview?
    var temporaryFolderID: String? { mergePreview?.folderID }
    var mergePreviewSourceFrame: CGRect? { mergePreview?.sourceFrame }
    @Published private(set) var folderNamingRequest: FolderNamingRequest?

    func cancelFolderNamingRequest(folderID: String? = nil) {
        if folderID == nil || folderNamingRequest?.folderID == folderID { folderNamingRequest = nil }
    }

    func consumeFolderNamingRequest(_ request: FolderNamingRequest) -> Bool {
        guard folderNamingRequest == request, !isPreviewingDrag,
              request.sessionID == dragSessionID, group(id: request.folderID)?.isFolder == true else { return false }
        folderNamingRequest = nil
        return true
    }

    @discardableResult
    func beginMergePreview(_ payload: DragPayload, targetGroupID: String, sourceFrame: CGRect = .zero) -> String? {
        guard isPreviewingDrag, mergePreview == nil,
              let appID = draggedAppID(payload),
              let app = allApps().first(where: { $0.id == appID }),
              let target = group(id: targetGroupID), !target.isFolder, target.apps.count == 1,
              let targetApp = target.apps.first, targetApp.id != appID else { return nil }
        let before = layout
        var next = layout
        Self.detach(appID, from: &next)
        guard let page = next.pages.firstIndex(where: { $0.groups.contains { $0.id == targetGroupID } }),
              let index = next.pages[page].groups.firstIndex(where: { $0.id == targetGroupID }) else { return nil }
        let id = UUID().uuidString
        next.pages[page].groups[index] = LaunchGroup(id: id, name: suggestedFolderName(for: [targetApp, app]),
                                                    isFolder: true, apps: [targetApp, app])
        mergePreview = MergePreview(sessionID: dragSessionID, folderID: id, before: before, sourceFrame: sourceFrame)
        markDragContainerChange(appID: appID)
        layout = next
        return id
    }

    func discardMergePreview() {
        guard let preview = mergePreview, preview.sessionID == dragSessionID, isPreviewingDrag else { return }
        mergePreview = nil
        layout = preview.before
    }

    // Register only after the native session has captured its dragging image.
    // App identity survives deletion/recreation of the outer group and its item.
    func registerDragAppearance(_ payload: DragPayload, sessionID: UUID) {
        guard isPreviewingDrag, sessionID == dragSessionID, dragAppearance == nil,
              let appID = draggedAppID(payload) else { return }
        dragAppearance = (sessionID, appID, false)
    }

    func suppressesDragContent(appID: String?) -> Bool {
        guard isPreviewingDrag, let appearance = dragAppearance,
              appearance.sessionID == dragSessionID else { return false }
        return appearance.crossedContainer && appearance.appID == appID
    }

    private func markDragContainerChange(appID: String) {
        guard dragAppearance?.sessionID == dragSessionID,
              dragAppearance?.appID == appID else { return }
        dragAppearance?.crossedContainer = true
    }

    func draggedAppID(_ payload: DragPayload) -> String? {
        switch payload {
        case .folderApp(let id, _): return id
        case .group(let id):
            let group = dragSnapshot?.pages.flatMap(\.groups).first { $0.id == id } ?? group(id: id)
            return group?.isFolder == false ? group?.apps.first?.id : nil
        }
    }

    func previewMove(_ payload: DragPayload, intoFolder folderID: String) {
        if let temporaryFolderID, temporaryFolderID != folderID { discardMergePreview() }
        guard isPreviewingDrag, group(id: folderID)?.isFolder == true,
              let appID = draggedAppID(payload),
              let source = layout.pages.flatMap(\.groups).first(where: { $0.apps.contains { $0.id == appID } }),
              source.id != folderID, let app = source.apps.first(where: { $0.id == appID }) else { return }
        markDragContainerChange(appID: appID)
        var next = layout
        Self.detach(appID, from: &next)
        guard let page = next.pages.firstIndex(where: { $0.groups.contains { $0.id == folderID } }),
              let index = next.pages[page].groups.firstIndex(where: { $0.id == folderID }) else { return }
        next.pages[page].groups[index].apps.append(app)
        layout = next
    }

    @discardableResult
    func previewMoveToPage(_ payload: DragPayload, page: Int) -> String? {
        guard isPreviewingDrag else { return nil }
        discardMergePreview()
        guard let appID = draggedAppID(payload) else {
            if case .group(let id) = payload { return id }
            return nil
        }
        guard let source = layout.pages.flatMap(\.groups).first(where: { $0.apps.contains { $0.id == appID } }),
              let app = source.apps.first(where: { $0.id == appID }) else { return nil }
        if !source.isFolder { return source.id }
        markDragContainerChange(appID: appID)
        var next = layout
        Self.detach(appID, from: &next)
        let id: String
        if case .group(let original) = payload { id = original }
        else { id = "drag-" + appID }
        let destination = min(max(page, 0), next.pages.count - 1)
        next.pages[destination].groups.append(LaunchGroup(id: id, name: "", isFolder: false, apps: [app]))
        layout = next
        return id
    }

    private static func detach(_ id: String, from layout: inout LaunchLayout) {
        for page in layout.pages.indices {
            for index in layout.pages[page].groups.indices {
                guard layout.pages[page].groups[index].apps.contains(where: { $0.id == id }) else { continue }
                layout.pages[page].groups[index].apps.removeAll { $0.id == id }
                collapseSingleton(&layout.pages[page].groups[index])
            }
            layout.pages[page].groups.removeAll { $0.apps.isEmpty }
        }
    }

    private static func collapseSingleton(_ group: inout LaunchGroup) {
        if group.isFolder, group.apps.count == 1 {
            group.isFolder = false
            group.name = ""
        }
    }

    static let shared = LayoutStore()

    private let fileManager = FileManager.default
    private let supportURL: URL
    private let layoutURL: URL

    private init() {
        supportURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/iLaunchPad", isDirectory: true)
        layoutURL = supportURL.appendingPathComponent("layout.json")

        if let data = try? Data(contentsOf: layoutURL),
           let saved = try? JSONDecoder.layoutDecoder.decode(LaunchLayout.self, from: data) {
            layout = saved
        } else if let imported = try? LaunchOSImporter.importLayout() {
            layout = imported
        } else {
            layout = LaunchLayout(pages: [LaunchPage(id: UUID().uuidString, groups: [])])
        }
        normalize()
        directoryMonitor = ApplicationDirectoryMonitor(roots: ApplicationScanner.roots) { [weak self] in
            ApplicationIconCache.shared.clear()
            self?.refreshInstalledApplications()
        }
        refreshInstalledApplications()
        save()
    }

    // Isolated storage for interaction regression tests; never scans real apps.
    init(layout: LaunchLayout, storageURL: URL) {
        self.layout = layout
        layoutURL = storageURL
        supportURL = storageURL.deletingLastPathComponent()
    }

    func beginDragPreview() {
        if dragSnapshot == nil {
            dragAppearance = nil
            mergePreview = nil
            folderNamingRequest = nil
            dragSnapshot = layout
            dragSessionID = UUID()
        }
    }

    func resetDragPreview() {
        mergePreview = nil
        if let snapshot = dragSnapshot { layout = snapshot }
    }

    func finishDragPreview(commit: Bool) {
        guard let snapshot = dragSnapshot else { return }
        let naming = mergePreview.flatMap { preview -> FolderNamingRequest? in
            guard commit, dragDestination == .folder(preview.folderID),
                  group(id: preview.folderID)?.isFolder == true,
                  (group(id: preview.folderID)?.apps.count ?? 0) >= 2 else { return nil }
            return FolderNamingRequest(sessionID: dragSessionID, folderID: preview.folderID)
        }
        if commit, mergePreview != nil, naming == nil { discardMergePreview() }
        mergePreview = nil
        dragSnapshot = nil
        dragDestination = nil
        dragAppearance = nil
        NotificationCenter.default.post(name: .launchpadDragFinished, object: self)
        if commit { cleanAndSave() }
        else { layout = snapshot }
        folderNamingRequest = naming
        if let apps = deferredScan {
            deferredScan = nil
            receiveScannedApplications(apps, generation: scanGeneration)
        }
    }

    func removeUninstalledApplication(_ app: LaunchApp) {
        for page in layout.pages.indices {
            for group in layout.pages[page].groups.indices {
                let previousCount = layout.pages[page].groups[group].apps.count
                layout.pages[page].groups[group].apps.removeAll { $0.id == app.id || $0.fileURL == app.fileURL }
                if layout.pages[page].groups[group].apps.count != previousCount {
                    Self.collapseSingleton(&layout.pages[page].groups[group])
                }
            }
            layout.pages[page].groups.removeAll { $0.apps.isEmpty }
        }
        ApplicationIconCache.shared.clear()
        cleanAndSave()
    }

    var pageCount: Int { max(layout.pages.count, 1) }

    func groups(on page: Int) -> [LaunchGroup] {
        guard layout.pages.indices.contains(page) else { return [] }
        return layout.pages[page].groups.filter { group in
            if group.isFolder { return !group.apps.isEmpty }
            return group.apps.first?.hidden != true
        }
    }

    func allApps() -> [LaunchApp] {
        layout.pages.flatMap(\.groups).flatMap(\.apps)
    }

    func group(id: String) -> LaunchGroup? {
        layout.pages.lazy.flatMap(\.groups).first(where: { $0.id == id })
    }

    func open(_ app: LaunchApp) {
        guard let url = resolvedURL(for: app) else {
            lastError = "找不到“\(app.name)”的应用文件"
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error {
                Task { @MainActor in self.lastError = "无法打开“\(app.name)”：\(error.localizedDescription)" }
            }
        }
    }

    func resolvedURL(for app: LaunchApp) -> URL? {
        if let url = app.fileURL, fileManager.fileExists(atPath: url.path) { return url }
        guard !app.bundleIdentifier.isEmpty else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier)
    }

    func showInFinder(_ app: LaunchApp) {
        guard let url = resolvedURL(for: app) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func hide(_ groupID: String) {
        mutateGroup(groupID) { group in
            guard !group.isFolder, !group.apps.isEmpty else { return }
            group.apps[0].hidden = true
        }
    }

    func renameFolder(_ groupID: String, name: String) {
        mutateGroup(groupID) { group in
            guard group.isFolder else { return }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            group.name = trimmed.isEmpty ? "未命名" : trimmed
        }
    }

    func moveGroup(_ sourceID: String, relativeTo targetID: String, side: DropSide) {
        guard sourceID != targetID,
              let source = groupLocation(sourceID),
              let target = groupLocation(targetID) else { return }
        let moving = layout.pages[source.page].groups.remove(at: source.index)
        var insertion = target.index
        if source.page == target.page, source.index < target.index { insertion -= 1 }
        if side == .after { insertion += 1 }
        insertion = min(max(0, insertion), layout.pages[target.page].groups.count)
        layout.pages[target.page].groups.insert(moving, at: insertion)
        cleanAndSave()
    }

    func moveGroup(_ sourceID: String, toPage page: Int) {
        guard let source = groupLocation(sourceID) else { return }
        let moving = layout.pages[source.page].groups.remove(at: source.index)
        while layout.pages.count <= page {
            layout.pages.append(LaunchPage(id: UUID().uuidString, groups: []))
        }
        layout.pages[page].groups.append(moving)
        cleanAndSave()
    }

    func dropGroup(_ sourceID: String, into targetID: String) {
        guard sourceID != targetID,
              let source = groupLocation(sourceID),
              let target = groupLocation(targetID) else { return }
        let moving = layout.pages[source.page].groups[source.index]
        let destination = layout.pages[target.page].groups[target.index]
        guard !moving.isFolder, moving.apps.count == 1, !destination.apps.isEmpty else { return }

        layout.pages[source.page].groups.remove(at: source.index)
        guard let adjustedTarget = groupLocation(targetID) else { return }
        if destination.isFolder {
            layout.pages[adjustedTarget.page].groups[adjustedTarget.index].apps.append(moving.apps[0])
        } else {
            let folderName = suggestedFolderName(for: [destination.apps[0], moving.apps[0]])
            layout.pages[adjustedTarget.page].groups[adjustedTarget.index] = LaunchGroup(
                id: UUID().uuidString,
                name: folderName,
                isFolder: true,
                apps: [destination.apps[0], moving.apps[0]]
            )
        }
        cleanAndSave()
    }

    func moveAppInsideFolder(_ appID: String, folderID: String, relativeTo targetID: String, side: DropSide) {
        mutateGroup(folderID) { folder in
            guard folder.isFolder,
                  let source = folder.apps.firstIndex(where: { $0.id == appID }),
                  let target = folder.apps.firstIndex(where: { $0.id == targetID }),
                  source != target else { return }
            let moving = folder.apps.remove(at: source)
            var insertion = target
            if source < target { insertion -= 1 }
            if side == .after { insertion += 1 }
            folder.apps.insert(moving, at: min(max(0, insertion), folder.apps.count))
        }
    }

    func removeFromFolder(_ appID: String, folderID: String, toPage page: Int) {
        guard let location = groupLocation(folderID),
              let appIndex = layout.pages[location.page].groups[location.index].apps.firstIndex(where: { $0.id == appID }) else { return }
        let app = layout.pages[location.page].groups[location.index].apps.remove(at: appIndex)
        Self.collapseSingleton(&layout.pages[location.page].groups[location.index])
        let group = LaunchGroup(id: UUID().uuidString, name: "", isFolder: false, apps: [app])
        let destination = min(max(page, 0), layout.pages.count - 1)
        layout.pages[destination].groups.append(group)
        cleanAndSave()
    }

    func restoreLaunchOSLayout() {
        do {
            layout = try LaunchOSImporter.importLayout()
            scanTask?.cancel()
            scanGeneration = UUID()
            deferredScan = nil
            normalize()
            save()
            refreshInstalledApplications()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshInstalledApplications() {
        scanInProgress = true
        lastScanStarted = Date()
        scanTask?.cancel()
        scanGeneration = UUID()
        deferredScan = nil
        let generation = scanGeneration
        scanTask = Task { [weak self] in
            let apps = await ApplicationScanner.scanInBackground()
            guard !Task.isCancelled else { return }
            self?.receiveScannedApplications(apps, generation: generation)
        }
    }

    func receiveScannedApplications(_ apps: [LaunchApp], generation: UUID) {
        guard generation == scanGeneration else { return }
        scanInProgress = false
        guard !isPreviewingDrag else { deferredScan = apps; return }
        var knownBundleIDs = Set(allApps().map(\.bundleIdentifier).filter { !$0.isEmpty })
        var knownPaths = Set(allApps().compactMap { $0.fileURL?.standardizedFileURL.path })
        var newApps: [LaunchApp] = []
        for app in apps {
            let path = app.fileURL?.standardizedFileURL.path ?? app.path
            guard !knownBundleIDs.contains(app.bundleIdentifier), !knownPaths.contains(path) else { continue }
            knownBundleIDs.insert(app.bundleIdentifier)
            knownPaths.insert(path)
            newApps.append(app)
        }
        guard !newApps.isEmpty else { return }

        for app in newApps {
            let page = ApplicationDiscoveryPolicy.insertionPage(groupCounts: layout.pages.map { $0.groups.count })
            if page == layout.pages.count {
                layout.pages.append(LaunchPage(id: UUID().uuidString, groups: []))
            }
            layout.pages[page].groups.append(
                LaunchGroup(id: UUID().uuidString, name: "", isFolder: false, apps: [app])
            )
            knownBundleIDs.insert(app.bundleIdentifier)
            knownPaths.insert(app.fileURL?.standardizedFileURL.path ?? app.path)
        }
        save()
    }

    func waitForApplicationScan() async { await scanTask?.value }

    func refreshApplicationsOnPresentation() {
        guard !scanInProgress, Date().timeIntervalSince(lastScanStarted) >= 20 else { return }
        refreshInstalledApplications()
    }

    func stopApplicationMonitoring() { directoryMonitor?.stop() }

    func showAllHiddenApps() {
        for page in layout.pages.indices {
            for group in layout.pages[page].groups.indices where !layout.pages[page].groups[group].isFolder {
                if !layout.pages[page].groups[group].apps.isEmpty {
                    layout.pages[page].groups[group].apps[0].hidden = false
                }
            }
        }
        objectWillChange.send()
        save()
    }

    private func groupLocation(_ id: String) -> (page: Int, index: Int)? {
        for page in layout.pages.indices {
            if let index = layout.pages[page].groups.firstIndex(where: { $0.id == id }) {
                return (page, index)
            }
        }
        return nil
    }

    private func mutateGroup(_ id: String, mutation: (inout LaunchGroup) -> Void) {
        guard let location = groupLocation(id) else { return }
        mutation(&layout.pages[location.page].groups[location.index])
        cleanAndSave()
    }

    private func suggestedFolderName(for apps: [LaunchApp]) -> String {
        let ids = apps.map(\.bundleIdentifier).joined(separator: " ").lowercased()
        if ids.contains("game") || ids.contains("steam") { return "游戏" }
        if ids.contains("developer") || ids.contains("xcode") || ids.contains("jetbrains") { return "开发工具" }
        if ids.contains("music") || ids.contains("video") || ids.contains("photo") { return "娱乐" }
        return "未命名"
    }

    private func normalize() {
        if layout.pages.isEmpty { layout.pages = [LaunchPage(id: UUID().uuidString, groups: [])] }
        var seen = Set<String>()
        for page in layout.pages.indices {
            layout.pages[page].groups = layout.pages[page].groups.compactMap { group in
                var copy = group
                copy.apps = group.apps.filter { app in
                    let key = app.bundleIdentifier.isEmpty ? app.id : app.bundleIdentifier
                    guard !seen.contains(key) else { return false }
                    seen.insert(key)
                    return true
                }
                return copy.apps.isEmpty ? nil : copy
            }
        }
    }

    private func cleanAndSave() {
        guard !isPreviewingDrag else { return }
        for page in layout.pages.indices { layout.pages[page].groups.removeAll { $0.apps.isEmpty } }
        layout.pages.removeAll(where: { $0.groups.isEmpty && layout.pages.count > 1 })
        if layout.pages.isEmpty { layout.pages = [LaunchPage(id: UUID().uuidString, groups: [])] }
        objectWillChange.send()
        save()
    }

    private func save() {
        guard !isPreviewingDrag else { return }
        do {
            try fileManager.createDirectory(at: supportURL, withIntermediateDirectories: true)
            let data = try JSONEncoder.layoutEncoder.encode(layout)
            try data.write(to: layoutURL, options: .atomic)
        } catch {
            lastError = "无法保存启动台布局：\(error.localizedDescription)"
        }
    }
}

private extension JSONEncoder {
    static var layoutEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var layoutDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
