import AppKit
@preconcurrency import Foundation
import UniformTypeIdentifiers

/// Encapsulates drag-and-drop / open-panel logic so ContentView stays clean.
enum FileDropDelegate {

    /// Resolves dropped items without changing their directory structure.
    @MainActor
    static func collectURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await resolveProvider(provider) {
                urls.append(url.standardizedFileURL)
            }
        }
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }

    @MainActor
    private static func resolveProvider(_ provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url.standardizedFileURL
        }
        if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
            return url.standardizedFileURL
        }
        return nil
    }

    /// Presents the system open panel and returns the chosen URLs.
    static func openPanel() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.title = "选择文件"
        panel.message = "选择要在 Doupi Viewer 中查看的文件"
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.map { $0.standardizedFileURL }
    }
}
