import Foundation

/// Built away from the UI thread, once per application-list change.
struct ApplicationSearchEntry: Sendable {
    let app: LaunchApp
    let name: String
    let romanized: String
    let initials: String
    let bundle: String

    init(app: LaunchApp) {
        self.app = app
        name = Self.normalize(app.name)
        let latin = Self.normalize(app.name.applyingTransform(.toLatin, reverse: false) ?? app.name)
        romanized = latin.replacingOccurrences(of: " ", with: "")
        initials = latin.split(separator: " ").compactMap(\.first).map(String.init).joined()
        bundle = Self.normalize(app.bundleIdentifier)
    }

    static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    func score(for query: String) -> Int? {
        if name == query { return 0 }
        if name.hasPrefix(query) { return 1 }
        if name.contains(query) { return 2 }
        if romanized.contains(query) || initials.hasPrefix(query) { return 3 }
        return bundle.contains(query) ? 4 : nil
    }
}
