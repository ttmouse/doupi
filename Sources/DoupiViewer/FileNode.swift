import Foundation

/// A node in the project file tree.
struct FileNode: Identifiable, Hashable {
    let id: String          // relative path from project root
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?

    var hasChildren: Bool { isDirectory && children != nil }

    /// Recursively scan a directory, returning sorted nodes (dirs first).
    static func scan(_ root: URL, ignoring excluded: Set<String> = FileNode.defaultExcluded) -> [FileNode] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var dirContents: [URL: [URL]] = [:]
        var isDirCache: [URL: Bool] = [:]

        for case let url as URL in enumerator {
            let relPath = url.path.replacingOccurrences(of: root.path + "/", with: "")
            let components = relPath.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            let topDir = String(components.first ?? "")

            // Skip excluded top-level directories
            if excluded.contains(topDir) {
                enumerator.skipDescendants()
                continue
            }

            let parent = url.deletingLastPathComponent()
            dirContents[parent, default: []].append(url)

            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            isDirCache[url] = isDir
        }

        func buildTree(_ dir: URL) -> [FileNode] {
            let items = dirContents[dir]?.sorted { a, b in
                let aDir = isDirCache[a] ?? false
                let bDir = isDirCache[b] ?? false
                if aDir != bDir { return aDir && !bDir }
                return a.lastPathComponent < b.lastPathComponent
            } ?? []

            return items.map { url in
                let isDir = isDirCache[url] ?? false
                let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
                return FileNode(
                    id: rel,
                    url: url,
                    name: url.lastPathComponent,
                    isDirectory: isDir,
                    children: isDir ? buildTree(url) : nil
                )
            }
        }

        return buildTree(root)
    }

    static let defaultExcluded: Set<String> = [
        ".build", ".git", ".alma-snapshots", ".reasonix",
        "node_modules", ".DS_Store", "dist", "build",
    ]
}
