import Foundation
import Combine

/// 一个挂载点：磁盘上的真实目录，在文件库中以普通文件夹出现。
/// 内容只读，不写入用户的虚拟文件树，也不做搬移或整理。
struct LibraryMount: Hashable, Sendable {
    let name: String
    let directory: URL

    /// Doupi 的归档目录直接摊在文件库根级，避免 下载 / Doupi / HTML 这样的多层折叠。
    static let all: [LibraryMount] = [
        LibraryMount(
            name: "HTML",
            directory: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads/Doupi/HTML")
        ),
        LibraryMount(
            name: "Markdown",
            directory: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads/Doupi/Markdown")
        ),
    ]
}

enum LibraryMountScanner {
    /// 文件库认得的文档类型；挂载点里其他格式一律忽略。
    static let extensions: Set<String> = ["html", "htm", "md", "markdown"]
    /// 递归收集挂载点下的文档。不跟随符号链接，也不进入 app 包等 bundle 目录。
    static func scan(_ mount: LibraryMount) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: mount.directory.path) else { return [] }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey]
        var documents: [URL] = []

        func visit(_ directory: URL) throws {
            let children = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
            )
            for child in children {
                let values = try child.resourceValues(forKeys: keys)
                guard values.isSymbolicLink != true, values.isPackage != true else { continue }
                if values.isRegularFile == true, extensions.contains(child.pathExtension.lowercased()) {
                    documents.append(child.standardizedFileURL)
                } else if values.isDirectory == true {
                    try visit(child)
                }
            }
        }

        try visit(mount.directory)
        return documents.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// 把扫描结果还原成与磁盘一致的文件夹树，交给侧边栏当普通文件夹渲染。
    /// 节点 id 由路径派生，保证每轮重建后行身份（展开状态、悬停）不跳变。
    static func tree(_ mount: LibraryMount, files: [URL]) -> LibraryFolder? {
        let rootURL = mount.directory.standardizedFileURL
        var rootNode = Node()
        for file in files {
            let components = Array(file.standardizedFileURL.pathComponents.dropFirst(rootURL.pathComponents.count))
            guard !components.isEmpty else { continue }
            rootNode.insert(components, file: file)
        }
        guard !rootNode.isEmpty else { return nil }
        return rootNode.build(name: mount.name, path: rootURL.path)
    }

    private struct Node {
        var files: [LibraryFile] = []
        var children: [String: Node] = [:]

        var isEmpty: Bool { files.isEmpty && children.isEmpty }

        mutating func insert(_ components: [String], file: URL) {
            if components.count == 1 {
                files.append(LibraryFile(id: stableID(file.path), sourceURL: file))
                return
            }
            var child = children[components[0]] ?? Node()
            child.insert(Array(components.dropFirst()), file: file)
            children[components[0]] = child
        }

        func build(name: String, path: String) -> LibraryFolder {
            LibraryFolder(
                id: stableID(path),
                name: name,
                sourcePath: path,
                folders: children.keys
                    .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                    .map { children[$0]!.build(name: $0, path: path + "/" + $0) },
                files: files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            )
        }
    }

    /// 路径 → 稳定 UUID（FNV-1a 双种子，取 16 字节）。
    private static func stableID(_ path: String) -> UUID {
        var first: UInt64 = 0xcbf2_9ce4_8422_2325
        var second: UInt64 = 0x9e37_79b9_7f4a_7c15
        for byte in path.utf8 {
            first = (first ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            second = (second &+ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: first >> (8 * UInt64(index)))
            bytes[8 + index] = UInt8(truncatingIfNeeded: second >> (8 * UInt64(index)))
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

@MainActor
final class LibraryMountIndex: ObservableObject {
    /// 每个挂载点一棵树，顺序与 `mounts` 一致。空目录不占位。
    @Published private(set) var folders: [LibraryFolder] = []
    @Published private(set) var errorMessage: String?

    private let mounts: [LibraryMount]
    private var isScanning = false

    init(mounts: [LibraryMount] = LibraryMount.all) {
        self.mounts = mounts
    }

    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let mounts = mounts
        do {
            let result = try await Task.detached(priority: .utility) {
                try mounts.compactMap { mount in
                    LibraryMountScanner.tree(mount, files: try LibraryMountScanner.scan(mount))
                }
            }.value
            if result != folders { folders = result }
            errorMessage = nil
        } catch {
            // 保留上一次成功的结果，不把读取失败伪装成空文件夹。
            errorMessage = "无法读取归档目录：\(error.localizedDescription)"
        }
    }

    func monitor(interval: Duration = .seconds(3)) async {
        while !Task.isCancelled {
            await refresh()
            do { try await Task.sleep(for: interval) }
            catch { return }
        }
    }
}
