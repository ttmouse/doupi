import AppKit
import SwiftUI

/// Shared image cache to avoid repeated disk reads.
private let imageCache: NSCache<NSURL, NSImage> = {
    let cache = NSCache<NSURL, NSImage>()
    cache.countLimit = 64
    return cache
}()

/// Displays common image formats via NSImageView.
struct ImageView: NSViewRepresentable {

    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignCenter
        imageView.animates = true  // animated GIF support
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        let nsURL = url as NSURL
        if let cached = imageCache.object(forKey: nsURL) {
            nsView.image = cached
            return
        }
        if let image = NSImage(contentsOf: url) {
            imageCache.setObject(image, forKey: nsURL)
            nsView.image = image
        }
    }
}
