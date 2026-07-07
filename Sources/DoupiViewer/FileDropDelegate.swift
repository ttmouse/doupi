import AppKit
import Foundation
import UniformTypeIdentifiers

/// Encapsulates drag-and-drop / open-panel logic so ContentView stays clean.
enum FileDropDelegate {

    /// Collects all renderable file URLs from drop providers,
    /// resolving directories recursively.
    static func collectRenderableFiles(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            guard let url = await resolveProvider(provider) else { continue }
            let standard = url.standardizedFileURL
            if isDirectory(standard) {
                urls.append(contentsOf: renderableFilesInDirectory(standard))
            } else if isRenderable(standard) {
                urls.append(standard)
            }
        }
        // Preserve insertion order, remove duplicates
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }

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

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func isRenderable(_ url: URL) -> Bool {
        FileInfo.from(url: url)?.isRenderable ?? false
    }

    /// Recursively collect renderable files, skipping hidden files and common excluded dirs.
    private static let excludedDirectories: Set<String> = [
        ".build", ".git", ".alma-snapshots", ".reasonix",
        "node_modules", ".DS_Store", "dist", "build",
        ".svn", ".hg", "Pods", ".dart_tool", ".next", ".turbo",
    ]

    private static func renderableFilesInDirectory(_ dir: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey]),
                  !(values.isHidden ?? false)
            else { continue }

            if values.isDirectory == true {
                if excludedDirectories.contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }

            if isRenderable(fileURL) {
                results.append(fileURL.standardizedFileURL)
            }
        }
        return results
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
