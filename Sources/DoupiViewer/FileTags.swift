import Foundation

/// Persistent tag store — maps file URLs to sets of tags.
/// Backed by UserDefaults (same pattern as FileHistory).
enum FileTags {
    private static let key = "DoupiFileTags"

    private static var cache: [URL: Set<String>]?

    // MARK: - Public API

    static func load() -> [URL: Set<String>] {
        if let cache = cache { return cache }
        let raw: [String: [String]] = UserDefaultsStorage.loadDict(forKey: key)
        var result = [URL: Set<String>]()
        for (key, values) in raw {
            if let url = URL(string: key)?.standardizedFileURL {
                result[url] = Set(values)
            }
        }
        cache = result
        return result
    }

    static func tags(for url: URL) -> Set<String> {
        load()[url.standardizedFileURL] ?? []
    }

    static func addTag(_ tag: String, to url: URL) {
        var dict = load()
        dict[url.standardizedFileURL, default: []].insert(tag)
        save(dict)
    }

    static func removeTag(_ tag: String, from url: URL) {
        var dict = load()
        let standard = url.standardizedFileURL
        dict[standard]?.remove(tag)
        if dict[standard]?.isEmpty == true {
            dict.removeValue(forKey: standard)
        }
        save(dict)
    }

    static func toggleTag(_ tag: String, for url: URL) {
        let standard = url.standardizedFileURL
        if tags(for: standard).contains(tag) {
            removeTag(tag, from: standard)
        } else {
            addTag(tag, to: standard)
        }
    }

    /// All unique tag names across all files, sorted.
    static func allTags() -> [String] {
        Set(load().values.flatMap { $0 }).sorted()
    }

    /// URLs tagged with the given tag.
    static func urls(for tag: String) -> [URL] {
        load().filter { $0.value.contains(tag) }.map(\.key)
    }

    // MARK: - Persistence

    private static func save(_ dict: [URL: Set<String>]) {
        cache = dict
        let encodable = dict.reduce(into: [String: [String]]()) { result, pair in
            result[pair.key.absoluteString] = Array(pair.value).sorted()
        }
        UserDefaultsStorage.save(encodable, forKey: key)
    }
}
