import Foundation

/// Generic JSON-backed UserDefaults storage.
/// Handles encoding/decoding boilerplate so callers only define the key and type.
enum UserDefaultsStorage {

    /// Decode a Codable value from UserDefaults.
    static func load<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(T.self, from: data)
        else { return nil }
        return value
    }

    /// Encode a Codable value to UserDefaults.
    static func save<T: Codable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Decode with a fallback to an empty array.
    static func loadArray<T: Codable>(_ type: T.Type, forKey key: String) -> [T] {
        load([T].self, forKey: key) ?? []
    }

    /// Decode with a fallback to an empty set (stored as array).
    static func loadSet<T: Codable & Hashable>(_ type: T.Type, forKey key: String) -> Set<T> {
        Set(loadArray(T.self, forKey: key))
    }

    /// Decode a dictionary with a fallback to empty.
    static func loadDict<K: Codable & Hashable, V: Codable>(forKey key: String) -> [K: V] {
        load([K: V].self, forKey: key) ?? [:]
    }
}
