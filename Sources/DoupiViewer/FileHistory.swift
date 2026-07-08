import Foundation

/// Persists recently opened files using UserDefaults.
enum FileHistory {
    private static let key = "DoupiRecentFiles"

    static func load() -> [URL] {
        // 标准化：将文件引用 URL（file:///.file/id=...）转为绝对路径
        UserDefaultsStorage.loadArray(URL.self, forKey: key).map { $0.standardizedFileURL }
    }

    static func add(_ url: URL) {
        var urls = load()
        let standard = url.standardizedFileURL
        guard !urls.contains(standard) else { return }  // already in history, don't reorder
        urls.insert(standard, at: 0)
        save(urls)
    }

    /// Add multiple new URLs at the front, preserving input order.
    static func bulkAdd(_ urls: [URL]) {
        var existing = load()
        let newUrls = urls.map { $0.standardizedFileURL }.filter { !existing.contains($0) }
        guard !newUrls.isEmpty else { return }
        existing.insert(contentsOf: newUrls, at: 0)
        save(existing)
    }

    static func contains(_ url: URL) -> Bool {
        load().contains(url.standardizedFileURL)
    }

    static func save(_ urls: [URL]) {
        UserDefaultsStorage.save(urls, forKey: key)
    }
}
