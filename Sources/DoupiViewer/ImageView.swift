import AppKit
import SwiftUI

/// Displays common image formats via NSImageView.
/// Uses ImageCache.shared for transparent memory caching.
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
        let targetURL = url
        context.coordinator.load(url: targetURL) { image in
            nsView.image = image
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        private var currentTask: Task<Void, Never>?

        func load(url: URL, completion: @escaping (NSImage?) -> Void) {
            currentTask?.cancel()
            currentTask = Task { @MainActor in
                // Check cache
                if let cached = await ImageCache.shared.image(for: url) {
                    completion(cached)
                    return
                }
                // Load from disk on background
                let image = await Task.detached(priority: .userInitiated) {
                    NSImage(contentsOf: url)
                }.value
                guard let image else { completion(nil); return }
                await ImageCache.shared.setImage(image, for: url)
                completion(image)
            }
        }
    }
}
