import Foundation

/// Persistent store for pinned file URLs — backed by UserDefaults.
enum PinnedFiles {
    private static let key = "DoupiPinnedFiles"

    static func load() -> Set<URL> {
        UserDefaultsStorage.loadSet(URL.self, forKey: key)
    }

    static func save(_ urls: Set<URL>) {
        UserDefaultsStorage.save(Array(urls), forKey: key)
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
}
