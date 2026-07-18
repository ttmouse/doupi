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

    static func moveFile(_ fileID: UUID, from sourceFolderID: UUID, to targetFolderID: UUID, in folders: inout [LibraryFolder]) {
        guard sourceFolderID != targetFolderID,
              let file = takeFile(fileID, from: sourceFolderID, in: &folders)
        else { return }

        var didMove = false
        _ = mutate(targetFolderID, in: &folders) { target in
            guard !target.files.contains(where: {
                $0.id == file.id || $0.sourceURL.standardizedFileURL == file.sourceURL.standardizedFileURL
            }) else { return }
            target.files.append(file)
            didMove = true
        }

        guard didMove else {
            _ = mutate(sourceFolderID, in: &folders) { $0.files.append(file) }
            return
        }
        save(folders)
    }

    static func moveFolder(
        _ folderID: UUID,
        from sourceParentID: UUID?,
        to targetFolderID: UUID,
        in folders: inout [LibraryFolder]
    ) {
        guard folderID != targetFolderID,
              !contains(targetFolderID, within: folderID, in: folders),
              let folder = takeFolder(folderID, from: sourceParentID, in: &folders)
        else { return }

        var didMove = false
        _ = mutate(targetFolderID, in: &folders) { target in
            guard !target.folders.contains(where: { $0.id == folder.id }) else { return }
            target.folders.append(folder)
            didMove = true
        }

        guard didMove else {
            restoreFolder(folder, to: sourceParentID, in: &folders)
            return
        }
        save(folders)
    }

    static func moveFileToInbox(_ fileID: UUID, from sourceFolderID: UUID, in folders: inout [LibraryFolder]) {
        let inboxID = ensureInbox(in: &folders)
        moveFile(fileID, from: sourceFolderID, to: inboxID, in: &folders)
    }

    static func moveFolderToRoot(_ folderID: UUID, from sourceParentID: UUID?, in folders: inout [LibraryFolder]) {
        guard sourceParentID != nil,
              let folder = takeFolder(folderID, from: sourceParentID, in: &folders)
        else { return }
        folders.append(folder)
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

    private static func takeFile(_ fileID: UUID, from folderID: UUID, in folders: inout [LibraryFolder]) -> LibraryFile? {
        var file: LibraryFile?
        _ = mutate(folderID, in: &folders) { folder in
            guard let index = folder.files.firstIndex(where: { $0.id == fileID }) else { return }
            file = folder.files.remove(at: index)
        }
        return file
    }

    private static func takeFolder(
        _ folderID: UUID,
        from parentID: UUID?,
        in folders: inout [LibraryFolder]
    ) -> LibraryFolder? {
        if let parentID {
            var folder: LibraryFolder?
            _ = mutate(parentID, in: &folders) { parent in
                guard let index = parent.folders.firstIndex(where: { $0.id == folderID }) else { return }
                folder = parent.folders.remove(at: index)
            }
            return folder
        }

        guard let index = folders.firstIndex(where: { $0.id == folderID }) else { return nil }
        return folders.remove(at: index)
    }

    private static func ensureInbox(in folders: inout [LibraryFolder]) -> UUID {
        if let inbox = folders.first(where: { $0.name == "未分类" && $0.folders.isEmpty }) {
            return inbox.id
        }
        let inbox = LibraryFolder(name: "未分类")
        folders.append(inbox)
        return inbox.id
    }

    private static func restoreFolder(_ folder: LibraryFolder, to parentID: UUID?, in folders: inout [LibraryFolder]) {
        if let parentID {
            _ = mutate(parentID, in: &folders) { $0.folders.append(folder) }
        } else {
            folders.append(folder)
        }
    }

    private static func contains(_ candidateID: UUID, within folderID: UUID, in folders: [LibraryFolder]) -> Bool {
        guard let folder = findFolder(folderID, in: folders) else { return false }
        return folder.folders.contains { child in
            child.id == candidateID || contains(candidateID, within: child.id, in: [child])
        }
    }

    private static func findFolder(_ id: UUID, in folders: [LibraryFolder]) -> LibraryFolder? {
        for folder in folders {
            if folder.id == id { return folder }
            if let child = findFolder(id, in: folder.folders) { return child }
        }
        return nil
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
