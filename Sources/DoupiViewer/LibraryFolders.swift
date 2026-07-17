import Foundation

/// A file reference managed by Doupi. The source file always remains on disk.
struct LibraryFile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var sourceURL: URL

    init(id: UUID = UUID(), name: String? = nil, sourceURL: URL) {
        self.id = id
        self.name = name ?? sourceURL.lastPathComponent
        self.sourceURL = sourceURL.standardizedFileURL
    }

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: sourceURL.path)
    }
}

/// A virtual folder in Doupi. Imported and manually-created folders share this model.
struct LibraryFolder: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var folders: [LibraryFolder]
    var files: [LibraryFile]

    init(
        id: UUID = UUID(),
        name: String,
        folders: [LibraryFolder] = [],
        files: [LibraryFile] = []
    ) {
        self.id = id
        self.name = name
        self.folders = folders
        self.files = files
    }
}

struct LibraryImport: Sendable {
    var folders: [LibraryFolder]
    var looseFiles: [LibraryFile]

    var allFileURLs: [URL] {
        looseFiles.map(\.sourceURL) + folders.flatMap(\.allFileURLs)
    }
}

private extension LibraryFolder {
    var allFileURLs: [URL] {
        files.map(\.sourceURL) + folders.flatMap(\.allFileURLs)
    }
}

/// Persists and mutates Doupi's virtual folder tree.
enum LibraryFolders {
    private static let key = "DoupiLibraryFolders"
    private static var cache: [LibraryFolder]?
    private static let saveQueue = DispatchQueue(label: "com.doupi.library-folders", qos: .utility)

    static func load() -> [LibraryFolder] {
        if let cache { return cache }
        guard let data = UserDefaults.standard.data(forKey: key),
              let folders = try? JSONDecoder().decode([LibraryFolder].self, from: data)
        else { return [] }
        cache = folders
        return folders
    }

    static func save(_ folders: [LibraryFolder]) {
        cache = folders
        saveQueue.async {
            guard let data = try? JSONEncoder().encode(folders) else { return }
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func createFolder(named name: String, parentID: UUID? = nil, in folders: inout [LibraryFolder]) {
        if let parentID {
            _ = mutate(parentID, in: &folders) { parent in
                parent.folders.append(LibraryFolder(name: uniqueName(name, among: parent.folders)))
            }
        } else {
            folders.append(LibraryFolder(name: uniqueName(name, among: folders)))
        }
        save(folders)
    }

    /// Performs filesystem traversal only. Safe to run away from the main actor.
    static func prepareImport(_ urls: [URL]) -> LibraryImport {
        let standardized = urls.map(\.standardizedFileURL)
        return LibraryImport(
            folders: standardized.filter(isDirectory).compactMap(buildFolder),
            looseFiles: standardized
                .filter { !isDirectory($0) && isRegularFile($0) }
                .map { LibraryFile(sourceURL: $0) }
        )
    }

    static func apply(_ imported: LibraryImport, into folders: inout [LibraryFolder]) {
        for var folder in imported.folders {
            folder.name = uniqueName(folder.name, among: folders)
            folders.append(folder)
        }

        if !imported.looseFiles.isEmpty {
            if let inboxIndex = folders.firstIndex(where: { $0.name == "未分类" }) {
                let existing = Set(folders[inboxIndex].files.map { $0.sourceURL.standardizedFileURL })
                folders[inboxIndex].files.append(contentsOf: imported.looseFiles
                    .filter { !existing.contains($0.sourceURL.standardizedFileURL) })
            } else {
                folders.append(LibraryFolder(name: "未分类", files: imported.looseFiles))
            }
        }
        save(folders)
    }

    static func apply(_ imported: LibraryImport, into folderID: UUID, in folders: inout [LibraryFolder]) {
        _ = mutate(folderID, in: &folders) { target in
            for var folder in imported.folders {
                folder.name = uniqueName(folder.name, among: target.folders)
                target.folders.append(folder)
            }

            let existingFiles = Set(target.files.map { $0.sourceURL.standardizedFileURL })
            target.files.append(contentsOf: imported.looseFiles
                .filter { !existingFiles.contains($0.sourceURL.standardizedFileURL) })
        }
        save(folders)
    }

    static func rename(_ id: UUID, to name: String, in folders: inout [LibraryFolder]) {
        _ = renameRecursive(id, to: name, in: &folders)
        save(folders)
    }

    static func removeFile(_ fileID: UUID, from folderID: UUID, in folders: inout [LibraryFolder]) {
        _ = mutate(folderID, in: &folders) { folder in
            folder.files.removeAll { $0.id == fileID }
        }
        save(folders)
    }

    static func removeFile(at url: URL, in folders: inout [LibraryFolder]) {
        let standard = url.standardizedFileURL
        removeFile(at: standard, from: &folders)
        save(folders)
    }

    static func replaceFileURL(_ url: URL, with renamedURL: URL, in folders: inout [LibraryFolder]) {
        replaceFileURLRecursively(url.standardizedFileURL, with: renamedURL.standardizedFileURL, in: &folders)
        save(folders)
    }

    static func remove(_ id: UUID, from folders: inout [LibraryFolder]) {
        if let index = folders.firstIndex(where: { $0.id == id }) {
            folders.remove(at: index)
            save(folders)
            return
        }
        for index in folders.indices {
            if remove(id, from: &folders[index].folders) {
                save(folders)
                return
            }
        }
    }

    private static func remove(_ id: UUID, from folders: inout [LibraryFolder]) -> Bool {
        if let index = folders.firstIndex(where: { $0.id == id }) {
            folders.remove(at: index)
            return true
        }
        for index in folders.indices where remove(id, from: &folders[index].folders) {
            return true
        }
        return false
    }

    private static func mutate(
        _ id: UUID,
        in folders: inout [LibraryFolder],
        change: (inout LibraryFolder) -> Void
    ) -> Bool {
        if let index = folders.firstIndex(where: { $0.id == id }) {
            change(&folders[index])
            return true
        }
        for index in folders.indices where mutate(id, in: &folders[index].folders, change: change) {
            return true
        }
        return false
    }

    private static func removeFile(at url: URL, from folders: inout [LibraryFolder]) {
        for index in folders.indices {
            folders[index].files.removeAll { $0.sourceURL.standardizedFileURL == url }
            removeFile(at: url, from: &folders[index].folders)
        }
    }

    private static func replaceFileURLRecursively(_ url: URL, with renamedURL: URL, in folders: inout [LibraryFolder]) {
        for index in folders.indices {
            for fileIndex in folders[index].files.indices where folders[index].files[fileIndex].sourceURL.standardizedFileURL == url {
                folders[index].files[fileIndex].sourceURL = renamedURL
                folders[index].files[fileIndex].name = renamedURL.lastPathComponent
            }
            replaceFileURLRecursively(url, with: renamedURL, in: &folders[index].folders)
        }
    }

    private static func renameRecursive(_ id: UUID, to name: String, in folders: inout [LibraryFolder]) -> Bool {
        if let index = folders.firstIndex(where: { $0.id == id }) {
            let siblings = folders.enumerated().filter { $0.offset != index }.map(\.element)
            folders[index].name = uniqueName(name, among: siblings)
            return true
        }
        for index in folders.indices where renameRecursive(id, to: name, in: &folders[index].folders) {
            return true
        }
        return false
    }

    private static func buildFolder(from directory: URL) -> LibraryFolder? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isHiddenKey]
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var folders: [LibraryFolder] = []
        var files: [LibraryFile] = []

        for child in children.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            guard let values = try? child.resourceValues(forKeys: keys),
                  values.isHidden != true
            else { continue }

            if values.isDirectory == true {
                guard !excludedDirectories.contains(child.lastPathComponent),
                      let folder = buildFolder(from: child)
                else { continue }
                folders.append(folder)
            } else if values.isRegularFile == true {
                files.append(LibraryFile(sourceURL: child))
            }
        }

        return LibraryFolder(name: directory.lastPathComponent, folders: folders, files: files)
    }

    private static func uniqueName(_ proposed: String, among folders: [LibraryFolder]) -> String {
        let existing = Set(folders.map(\.name))
        guard existing.contains(proposed) else { return proposed }
        var suffix = 2
        while existing.contains("\(proposed) \(suffix)") { suffix += 1 }
        return "\(proposed) \(suffix)"
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
    }

    private static let excludedDirectories: Set<String> = [
        ".build", ".git", ".alma-snapshots", ".reasonix", "node_modules",
        "dist", "build", ".svn", ".hg", "Pods", ".dart_tool", ".next", ".turbo",
    ]
}
