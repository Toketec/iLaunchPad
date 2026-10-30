import Foundation

enum ApplicationDiscoveryPolicy {
    static let pageCapacity = 35

    // Returning count means a new page is needed. Never repack existing pages.
    static func insertionPage(groupCounts: [Int]) -> Int {
        groupCounts.firstIndex { $0 < pageCapacity } ?? groupCounts.count
    }
}
