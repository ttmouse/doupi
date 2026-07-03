import Foundation

/// Persists recently opened files using UserDefaults.
enum FileHistory {
    private static let key = "DoupiRecentFiles"
    private static let maxItems = 20

    static func load() -> [URL] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let urls = try? JSONDecoder().decode([URL].self, from: data)
        else { return [] }
        return urls
    }

    static func add(_ url: URL) {
        var urls = load()
        urls.removeAll { $0 == url }
        urls.insert(url, at: 0)
        if urls.count > maxItems { urls = Array(urls.prefix(maxItems)) }
        save(urls)
    }

    static func save(_ urls: [URL]) {
        guard let data = try? JSONEncoder().encode(urls) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
