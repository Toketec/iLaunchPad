import Foundation

struct LayoutBackupSummary: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let updatedAt: Date
}

struct LayoutBackup: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    let createdAt: Date
    var updatedAt: Date
    var layout: LaunchLayout
}

struct LayoutBackupCatalog: Codable, Sendable {
    var version = 1
    var backups: [LayoutBackup] = []
}

enum LayoutBackupError: LocalizedError {
    case limitReached
    case invalidName
    case missingBackup
    case emptyApplicationScan
    case dragInProgress

    var errorDescription: String? {
        switch self {
        case .limitReached: return "最多只能保存 3 份自定义布局"
        case .invalidName: return "请输入布局名称"
        case .missingBackup: return "找不到这份布局备份"
        case .emptyApplicationScan: return "没有读取到已安装应用，已保留当前布局"
        case .dragInProgress: return "请先结束当前拖拽，再切换布局"
        }
    }
}

final class LayoutBackupRepository {
    static let maximumCount = 3

    private let fileURL: URL
    private(set) var catalog: LayoutBackupCatalog
    private(set) var loadErrorDescription: String?

    init(fileURL: URL) {
        self.fileURL = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            catalog = LayoutBackupCatalog()
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            var decoded = try Self.decoder.decode(LayoutBackupCatalog.self, from: data)
            decoded.backups = Array(decoded.backups.prefix(Self.maximumCount))
            catalog = decoded
        } catch {
            catalog = LayoutBackupCatalog()
            loadErrorDescription = "布局备份文件无法读取，当前布局未受影响：\(error.localizedDescription)"
        }
    }

    var summaries: [LayoutBackupSummary] {
        catalog.backups.map { LayoutBackupSummary(id: $0.id, name: $0.name, updatedAt: $0.updatedAt) }
    }

    func layout(for id: String) -> LaunchLayout? {
        catalog.backups.first(where: { $0.id == id })?.layout
    }

    @discardableResult
    func create(name: String, layout: LaunchLayout) throws -> LayoutBackup {
        guard catalog.backups.count < Self.maximumCount else { throw LayoutBackupError.limitReached }
        let normalizedName = try uniqueName(for: name, excluding: nil)
        let now = Date()
        let backup = LayoutBackup(id: UUID().uuidString, name: normalizedName,
                                  createdAt: now, updatedAt: now, layout: layout)
        let previous = catalog
        catalog.backups.append(backup)
        do { try save() } catch { catalog = previous; throw error }
        return backup
    }

    func overwrite(id: String, layout: LaunchLayout) throws {
        guard let index = catalog.backups.firstIndex(where: { $0.id == id }) else {
            throw LayoutBackupError.missingBackup
        }
        let previous = catalog
        catalog.backups[index].layout = layout
        catalog.backups[index].updatedAt = Date()
        do { try save() } catch { catalog = previous; throw error }
    }

    func rename(id: String, name: String) throws {
        guard let index = catalog.backups.firstIndex(where: { $0.id == id }) else {
            throw LayoutBackupError.missingBackup
        }
        let previous = catalog
        catalog.backups[index].name = try uniqueName(for: name, excluding: id)
        catalog.backups[index].updatedAt = Date()
        do { try save() } catch { catalog = previous; throw error }
    }

    func delete(id: String) throws {
        guard catalog.backups.contains(where: { $0.id == id }) else {
            throw LayoutBackupError.missingBackup
        }
        let previous = catalog
        catalog.backups.removeAll { $0.id == id }
        do { try save() } catch { catalog = previous; throw error }
    }

    private func uniqueName(for proposed: String, excluding id: String?) throws -> String {
        let base = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { throw LayoutBackupError.invalidName }
        let used = Set(catalog.backups.filter { $0.id != id }.map { $0.name.lowercased() })
        guard used.contains(base.lowercased()) else { return base }
        var suffix = 2
        while used.contains("\(base) \(suffix)".lowercased()) { suffix += 1 }
        return "\(base) \(suffix)"
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try Self.encoder.encode(catalog)
        try data.write(to: fileURL, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum InstalledApplicationReconciler {
    static func reconcile(_ source: LaunchLayout, with installedApps: [LaunchApp]) -> LaunchLayout {
        guard !installedApps.isEmpty else { return source }

        var byBundleID: [String: LaunchApp] = [:]
        var byPath: [String: LaunchApp] = [:]
        for app in installedApps {
            if !app.bundleIdentifier.isEmpty { byBundleID[app.bundleIdentifier] = app }
            byPath[standardPath(app)] = app
        }

        var consumed = Set<String>()
        var pages: [LaunchPage] = []
        for page in source.pages {
            var groups: [LaunchGroup] = []
            for group in page.groups {
                var copy = group
                copy.apps = group.apps.compactMap { existing in
                    let installed = (!existing.bundleIdentifier.isEmpty ? byBundleID[existing.bundleIdentifier] : nil)
                        ?? byPath[standardPath(existing)]
                    guard let installed else { return nil }
                    let key = identity(installed)
                    guard consumed.insert(key).inserted else { return nil }
                    return LaunchApp(id: existing.id, name: installed.name,
                                     bundleIdentifier: installed.bundleIdentifier,
                                     path: installed.path, hidden: existing.hidden)
                }
                guard !copy.apps.isEmpty else { continue }
                if copy.isFolder, copy.apps.count == 1 {
                    copy.isFolder = false
                    copy.name = ""
                }
                groups.append(copy)
            }
            if !groups.isEmpty { pages.append(LaunchPage(id: page.id, groups: groups)) }
        }
        if pages.isEmpty { pages = [LaunchPage(id: UUID().uuidString, groups: [])] }

        let remaining = installedApps
            .filter { !consumed.contains(identity($0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for app in remaining {
            let page = ApplicationDiscoveryPolicy.insertionPage(groupCounts: pages.map { $0.groups.count })
            if page == pages.count { pages.append(LaunchPage(id: UUID().uuidString, groups: [])) }
            pages[page].groups.append(LaunchGroup(id: UUID().uuidString, name: "", isFolder: false, apps: [app]))
            consumed.insert(identity(app))
        }

        return LaunchLayout(version: source.version, importedFrom: source.importedFrom,
                            importedAt: source.importedAt, pages: pages)
    }

    private static func identity(_ app: LaunchApp) -> String {
        app.bundleIdentifier.isEmpty ? standardPath(app) : "bundle:\(app.bundleIdentifier)"
    }

    private static func standardPath(_ app: LaunchApp) -> String {
        app.fileURL?.standardizedFileURL.path ?? app.path
    }
}

enum AppleDefaultLayoutFactory {
    private static let primaryBundleIDs = [
        "com.apple.Safari", "com.apple.mail", "com.apple.AddressBook", "com.apple.iCal",
        "com.apple.reminders", "com.apple.Notes", "com.apple.Maps", "com.apple.findmy",
        "com.apple.MobileSMS", "com.apple.FaceTime", "com.apple.PhotoBooth", "com.apple.Photos",
        "com.apple.iMovieApp", "com.apple.garageband10", "com.apple.Music", "com.apple.TV",
        "com.apple.podcasts", "com.apple.iBooksX", "com.apple.AppStore", "com.apple.Pages",
        "com.apple.Numbers", "com.apple.Keynote", "com.apple.Preview", "com.apple.Dictionary",
        "com.apple.calculator", "com.apple.Chess", "com.apple.exposelauncher",
        "com.apple.systempreferences", "com.apple.siri.launcher", "com.apple.shortcuts",
        "com.apple.freeform", "com.apple.Home", "com.apple.weather", "com.apple.stocks",
        "com.apple.VoiceMemos", "com.apple.Passwords", "com.apple.ScreenContinuity",
        "com.apple.GenerativePlaygroundApp", "com.apple.clock", "com.apple.news",
        "com.apple.QuickTimePlayerX"
    ]

    private static let utilityBundleIDs = [
        "com.apple.airport.airportutility", "com.apple.grapher", "com.apple.ScreenSharing",
        "com.apple.screenshot.launcher", "com.apple.printcenter", "com.apple.Console", "com.apple.Magnifier",
        "com.apple.DigitalColorMeter", "com.apple.VoiceOverUtility", "com.apple.ActivityMonitor",
        "com.apple.DiskUtility", "com.apple.SystemProfiler", "com.apple.Terminal", "com.apple.ScriptEditor2",
        "com.apple.ColorSyncUtility", "com.apple.BluetoothFileExchange", "com.apple.MigrateAssistant",
        "com.apple.audio.AudioMIDISetup"
    ]

    static func make(from installedApps: [LaunchApp]) -> LaunchLayout {
        var byBundleID: [String: LaunchApp] = [:]
        for app in installedApps where !app.bundleIdentifier.isEmpty {
            byBundleID[app.bundleIdentifier] = app
        }
        var consumed = Set<String>()
        var priorityApps: [LaunchApp] = []
        for id in primaryBundleIDs {
            guard let app = byBundleID[id] else { continue }
            consumed.insert(id)
            priorityApps.append(app)
        }
        let utilities = utilityBundleIDs.compactMap { id -> LaunchApp? in
            guard let app = byBundleID[id] else { return nil }
            consumed.insert(id)
            return app
        }
        let firstPageAppLimit = utilities.isEmpty ? 35 : 34
        var firstPageGroups = priorityApps.prefix(firstPageAppLimit).map(singleGroup)
        if !utilities.isEmpty {
            firstPageGroups.append(LaunchGroup(id: "apple-default-folder-utilities", name: "其他",
                                               isFolder: true, apps: utilities))
        }

        let remaining = Array(priorityApps.dropFirst(firstPageAppLimit)) + installedApps
            .filter { !consumed.contains($0.bundleIdentifier) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var pages: [LaunchPage] = []
        if !firstPageGroups.isEmpty {
            pages.append(LaunchPage(id: "apple-default-page-1", groups: firstPageGroups))
        }
        if !remaining.isEmpty, !firstPageGroups.isEmpty {
            pages.append(LaunchPage(id: "apple-default-page-2", groups: []))
        }
        for app in remaining {
            if pages.isEmpty || pages.last!.groups.count >= 35 {
                pages.append(LaunchPage(id: UUID().uuidString, groups: []))
            }
            pages[pages.count - 1].groups.append(singleGroup(for: app))
        }
        if pages.isEmpty { pages = [LaunchPage(id: "apple-default-page-1", groups: [])] }
        return LaunchLayout(version: 1, importedFrom: "apple-default", importedAt: Date(), pages: pages)
    }

    private static func singleGroup(for app: LaunchApp) -> LaunchGroup {
        LaunchGroup(id: "apple-default-\(app.bundleIdentifier)", name: "", isFolder: false, apps: [app])
    }
}

extension Notification.Name {
    static let launchpadLayoutRestored = Notification.Name("iLaunchPad.layoutRestored")
}
