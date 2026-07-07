import Foundation

/// Persists recently opened files using UserDefaults.
enum FileHistory {
    private static let key = "DoupiRecentFiles"
    private static let maxItems = 20

    static func load() -> [URL] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let urls = try? JSONDecoder().decode([URL].self, from: data)
        else { return [] }
        // 标准化：将文件引用 URL（file:///.file/id=...）转为绝对路径
        return urls.map { $0.standardizedFileURL }
    }

    static func add(_ url: URL) {
        var urls = load()
        let standard = url.standardizedFileURL
        guard !urls.contains(standard) else { return }  // already in history, don't reorder
        urls.insert(standard, at: 0)
        if urls.count > maxItems { urls = Array(urls.prefix(maxItems)) }
        save(urls)
    }

    static func contains(_ url: URL) -> Bool {
        let standard = url.standardizedFileURL
        return load().contains(standard)
    }

    static func save(_ urls: [URL]) {
        guard let data = try? JSONEncoder().encode(urls) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
