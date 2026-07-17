import Foundation

/// Persists recently opened files using UserDefaults.
enum FileHistory {
    private static let key = "DoupiRecentFiles"
    private static let limit = 20

    static func load() -> [URL] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let urls = try? JSONDecoder().decode([URL].self, from: data)
        else { return [] }
        // 标准化：将文件引用 URL（file:///.file/id=...）转为绝对路径
        return Array(urls.map { $0.standardizedFileURL }.prefix(limit))
    }

    static func add(_ url: URL) {
        var urls = load()
        let standard = url.standardizedFileURL
        urls.removeAll { $0 == standard }
        urls.insert(standard, at: 0)
        save(urls)
    }

    static func contains(_ url: URL) -> Bool {
        let standard = url.standardizedFileURL
        return load().contains(standard)
    }

    static func remove(_ url: URL) {
        let standard = url.standardizedFileURL
        save(load().filter { $0 != standard })
    }

    static func replace(_ url: URL, with renamedURL: URL) {
        let standard = url.standardizedFileURL
        let renamed = renamedURL.standardizedFileURL
        save(load().map { $0 == standard ? renamed : $0 })
    }

    static func save(_ urls: [URL]) {
        guard let data = try? JSONEncoder().encode(Array(urls.prefix(limit))) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
