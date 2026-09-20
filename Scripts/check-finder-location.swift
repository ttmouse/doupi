import Foundation

/// 文件夹右键「在访达中显示」的回归检查。
///
/// 规则：live 挂载点用自己的磁盘路径；虚拟文件夹只有内容全在同一真实目录时才认那一处；
/// 说不清位置就返回 nil（右键里不出现这一项）。
@main
struct FinderLocationChecks {
    static func main() throws {
        let fm = FileManager.default
        // FileManager hands back physical paths (/private/tmp, not /tmp), so the
        // fixture root must be canonical before any URL is compared.
        let root = URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath()
            .appendingPathComponent("doupi-finder-location-check-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        func touch(_ path: String) throws -> URL {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "x".write(to: url, atomically: true, encoding: .utf8)
            return url.standardizedFileURL
        }

        /// 比路径而不是比 URL：目录 URL 带不带结尾斜杠取决于它是怎么推出来的，
        /// 那对用户没有意义，真正要断言的是「落到哪个目录」。
        func expect(_ folder: LibraryFolder, at expected: URL?, _ message: String) {
            let actual = folder.finderLocation
            precondition(actual?.path == expected?.standardizedFileURL.path, message)
            if let actual {
                precondition(actual.hasDirectoryPath, "\(message)（落点应当是目录 URL）")
            }
        }

        // 1. live 挂载点：自己的目录就是落点
        let htmlDir = root.appendingPathComponent("HTML")
        try fm.createDirectory(at: htmlDir, withIntermediateDirectories: true)
        let live = LibraryFolder(name: "HTML", sourcePath: htmlDir.path)
        expect(live, at: htmlDir, "live 文件夹应落在自己的磁盘目录")

        // 2. live 目录已消失：不假装能去
        expect(LibraryFolder(name: "Gone", sourcePath: root.appendingPathComponent("Gone").path), at: nil,
               "磁盘上不存在的目录不该给出落点")

        // 3. 虚拟文件夹，文件都在同一个真实目录
        let batch = root.appendingPathComponent("batch")
        let one = LibraryFile(sourceURL: try touch("batch/a.html"))
        let two = LibraryFile(sourceURL: try touch("batch/b.html"))
        expect(LibraryFolder(name: "项目", files: [one, two]), at: batch,
               "内容同源的虚拟文件夹应指向那一份目录")

        // 4. 虚拟子文件夹里的文件与父级同源，整体仍算同一处
        let sameDir = LibraryFile(sourceURL: try touch("batch/notes.html"))
        let nested = LibraryFolder(
            name: "项目",
            folders: [LibraryFolder(name: "草稿", files: [sameDir])],
            files: [one, two]
        )
        expect(nested, at: batch, "子文件夹的文件与父级同源时，父级仍能定位到共同目录")

        // 5. 子文件夹落在另一个真实目录：到父级这一层已经说不清是哪一个
        let foreignNested = LibraryFolder(
            name: "项目",
            folders: [LibraryFolder(name: "草稿", files: [
                LibraryFile(sourceURL: try touch("batch/drafts/c.html")),
            ])],
            files: [one, two]
        )
        expect(foreignNested, at: nil, "子文件夹另在一个目录时，父级不给落点")

        // 6. 来源分散：两个真实目录，说不清是哪一个
        expect(LibraryFolder(name: "混合", files: [
            one,
            LibraryFile(sourceURL: try touch("elsewhere/d.html")),
        ]), at: nil, "来源分散时不该猜一个目录")

        // 7. 空文件夹：没有文件可依据
        expect(LibraryFolder(name: "新建文件夹"), at: nil, "空文件夹没有落点")

        // 8. 文件已从磁盘删除：父目录也没了，落点作废
        expect(LibraryFolder(name: "已删", files: [
            LibraryFile(sourceURL: root.appendingPathComponent("vanished/e.html").standardizedFileURL),
        ]), at: nil, "文件所在的目录已不存在时不给落点")

        print("PASS: all finder location regression checks")
    }
}
