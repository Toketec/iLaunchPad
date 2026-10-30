import Foundation

struct LaunchApp: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var bundleIdentifier: String
    var path: String
    var hidden: Bool = false

    var fileURL: URL? {
        if path.hasPrefix("file://") {
            return URL(string: path)
        }
        return URL(fileURLWithPath: path)
    }
}

struct LaunchGroup: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var isFolder: Bool
    var apps: [LaunchApp]

    var displayName: String {
        if isFolder { return name.isEmpty ? "未命名" : name }
        return apps.first?.name ?? name
    }
}

struct LaunchPage: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var groups: [LaunchGroup]
}

struct LaunchLayout: Codable, Sendable {
    var version: Int = 1
    var importedFrom: String?
    var importedAt: Date?
    var pages: [LaunchPage]
}

enum DropSide: Sendable {
    case before
    case after
}
