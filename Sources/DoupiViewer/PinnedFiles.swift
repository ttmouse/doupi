import Foundation

/// Persistent store for pinned file URLs — backed by UserDefaults.
enum PinnedFiles {
    private static let key = "DoupiPinnedFiles"

    static func load() -> Set<URL> {
        guard let data = UserDefaults.standard.data(forKey: key),
              let urls = try? JSONDecoder().decode([URL].self, from: data)
        else { return [] }
        return Set(urls.map { $0.standardizedFileURL })
    }

    static func save(_ urls: Set<URL>) {
        guard let data = try? JSONEncoder().encode(Array(urls)) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func isPinned(_ url: URL) -> Bool {
        load().contains(url.standardizedFileURL)
    }

    static func toggle(_ url: URL) {
        var pinned = load()
        let standard = url.standardizedFileURL
        if pinned.contains(standard) {
            pinned.remove(standard)
        } else {
            pinned.insert(standard)
        }
        save(pinned)
    }


    static func remove(_ url: URL) {
        var pinned = load()
        pinned.remove(url.standardizedFileURL)
        save(pinned)
    }

    static func replace(_ url: URL, with renamedURL: URL) {
        var pinned = load()
        guard pinned.remove(url.standardizedFileURL) != nil else { return }
        pinned.insert(renamedURL.standardizedFileURL)
        save(pinned)
    }
}
