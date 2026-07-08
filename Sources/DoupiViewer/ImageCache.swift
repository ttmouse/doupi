import AppKit

/// Thread-safe image cache with LRU eviction (count limit = 64).
actor ImageCache {
    static let shared = ImageCache()

    private let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 64
        return c
    }()

    private init() {}

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func setImage(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }

    /// Load from disk if not cached.
    func load(from url: URL) -> NSImage? {
        if let cached = image(for: url) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        setImage(image, for: url)
        return image
    }
}
