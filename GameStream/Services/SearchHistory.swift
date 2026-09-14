import Foundation

enum SearchHistory {
    private static let pinnedKey = "GameStream.pinnedSearches"

    static var pinned: [String] {
        UserDefaults.standard.stringArray(forKey: pinnedKey) ?? []
    }

    static func isPinned(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return pinned.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    static func togglePin(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = pinned
        if let idx = items.firstIndex(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            items.remove(at: idx)
        } else {
            items.insert(trimmed, at: 0)
            if items.count > 12 { items = Array(items.prefix(12)) }
        }
        UserDefaults.standard.set(items, forKey: pinnedKey)
    }
}
