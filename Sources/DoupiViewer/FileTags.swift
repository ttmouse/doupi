import Foundation

/// Persistent tag store — maps file URLs to sets of tags.
/// Backed by UserDefaults (same pattern as FileHistory).
enum FileTags {
    private static let key = "DoupiFileTags"

    private static var cache: [URL: Set<String>]?

    // MARK: - Public API

    static func load() -> [URL: Set<String>] {
        if let cache = cache { return cache }
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            cache = [:]
            return cache!
        }
        cache = dict.reduce(into: [:]) { result, pair in
            if let url = URL(string: pair.key)?.standardizedFileURL {
                result[url] = Set(pair.value)
            }
        }
        return cache!
    }

    static func tags(for url: URL) -> Set<String> {
        let standard = url.standardizedFileURL
        return load()[standard] ?? []
    }

    static func addTag(_ tag: String, to url: URL) {
        var dict = load()
        let standard = url.standardizedFileURL
        dict[standard, default: []].insert(tag)
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

    static func removeAllTags(from url: URL) {
        var dict = load()
        dict.removeValue(forKey: url.standardizedFileURL)
        save(dict)
    }

    static func replaceURL(_ url: URL, with renamedURL: URL) {
        var dict = load()
        guard let tags = dict.removeValue(forKey: url.standardizedFileURL) else { return }
        dict[renamedURL.standardizedFileURL, default: []].formUnion(tags)
        save(dict)
    }

    /// All unique tag names across all files, sorted.
    static func allTags() -> [String] {
        let dict = load()
        let tags = Set(dict.values.flatMap { $0 })
        return tags.sorted()
    }

    /// URLs tagged with the given tag.
    static func urls(for tag: String) -> [URL] {
        let dict = load()
        return dict.filter { $0.value.contains(tag) }.map(\.key)
    }

    // MARK: - Persistence

    private static func save(_ dict: [URL: Set<String>]) {
        cache = dict
        let encodable = dict.reduce(into: [String: [String]]()) { result, pair in
            result[pair.key.absoluteString] = Array(pair.value).sorted()
        }
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
