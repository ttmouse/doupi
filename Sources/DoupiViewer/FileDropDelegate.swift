import AppKit
import Foundation
import UniformTypeIdentifiers

/// Encapsulates drag-and-drop / open-panel logic so ContentView stays clean.
enum FileDropDelegate {

    /// Returns the first file URL from an array of NSItemProvider instances.
    /// Called inside `.onDrop` / `.onOpenURL` handlers.
    static func handleDrop(_ providers: [NSItemProvider]) async -> URL? {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    return url.standardizedFileURL
                }
                if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                    return url.standardizedFileURL
                }
            }
        }
        return nil
    }

    /// Presents the system open panel and returns the chosen URL.
    static func openPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "选择文件"
        panel.message = "选择要在 Doupi Viewer 中查看的文件"
        return panel.runModal() == .OK ? panel.url?.standardizedFileURL : nil
    }
}
