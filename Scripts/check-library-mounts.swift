import Foundation

@main
struct LibraryMountChecks {
    @MainActor
    static func main() async throws {
        let fm = FileManager.default
        // FileManager hands back physical paths (/private/tmp, not /tmp), so the
        // fixture root must be canonical before any URL is compared.
        let root = URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath()
            .appendingPathComponent("doupi-mounts-check-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let htmlDir = root.appendingPathComponent("HTML")
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: htmlDir.path) }

        func write(_ path: String) throws -> URL {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "# Fixture".write(to: url, atomically: true, encoding: .utf8)
            return url.standardizedFileURL
        }
        func mount(_ name: String) -> LibraryMount {
            LibraryMount(name: name, directory: root.appendingPathComponent(name))
        }

        let html = mount("HTML")
        let markdown = mount("Markdown")

        let page = try write("HTML/page.HTML")
        let deepPage = try write("HTML/site/deep/other.htm")
        let note = try write("Markdown/note.md")
        let deepNote = try write("Markdown/nested/deep.markdown")
        _ = try write("HTML/photo.png")
        _ = try write("Markdown/Untitled.txt")
        _ = try write("HTML/Test.app/Contents/internal.html")
        _ = try write("HTML/.hidden/secret.html")
        try fm.createSymbolicLink(at: root.appendingPathComponent("HTML/loop"), withDestinationURL: root)

        let expected = Set([page, deepPage, note, deepNote])
        let htmlScan = try LibraryMountScanner.scan(html)
        let markdownScan = try LibraryMountScanner.scan(markdown)
        precondition(Set(htmlScan) == Set([page, deepPage]),
                     "HTML mount must collect html/htm recursively")
        precondition(Set(markdownScan) == Set([note, deepNote]),
                     "Markdown mount must collect md/markdown recursively")
        precondition(Set(LibraryMountScanner.extensions) == Set(["html", "htm", "md", "markdown"]),
                     "Both mounts must share one document extension set")
        print("PASS: mounts flatten to their directory; hidden files, apps, links and other formats excluded")

        let htmlTree = try unwrap(LibraryMountScanner.tree(html, files: htmlScan))
        precondition(htmlTree.name == "HTML" && htmlTree.sourcePath == htmlDir.path,
                     "Mount node carries the real directory path")
        precondition(htmlTree.folders.map(\.name) == ["site"] && htmlTree.files.map(\.name) == ["page.HTML"],
                     "Folder rows precede file rows and sort deterministically")
        let site = try unwrap(htmlTree.folders.first)
        precondition(site.folders.map(\.name) == ["deep"],
                     "Deep nesting below a mount is preserved")
        let htmlTreeAgain = LibraryMountScanner.tree(html, files: htmlScan)
        precondition(htmlTreeAgain == htmlTree,
                     "Tree ids must be stable so rows keep identity across refreshes")
        let emptyDir = root.appendingPathComponent("Empty")
        try fm.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        precondition(LibraryMountScanner.tree(mount("Empty"), files: []) == nil,
                     "An empty mount must not occupy a sidebar row")
        let missing = try LibraryMountScanner.scan(mount("Missing"))
        precondition(missing.isEmpty,
                     "A mount without a directory scans as empty instead of failing")
        print("PASS: each mount renders as a stable folder tree; empty mounts stay hidden")

        let index = LibraryMountIndex(mounts: [html, markdown])
        let monitor = Task { await index.monitor(interval: .milliseconds(40)) }
        try await waitUntil { Set(files(in: index.folders)) == expected }
        precondition(index.folders.map(\.name) == ["HTML", "Markdown"],
                     "Mount order must follow the declared order; got \(index.folders.map(\.name))")
        precondition(index.errorMessage == nil, "A successful scan must clear the error banner")

        let fresh = try write("Markdown/fresh.md")
        try await waitUntil { files(in: index.folders).contains(fresh) }
        print("PASS: the rendered tree picks up new documents without reopening the view")

        let moved = root.appendingPathComponent("HTML/page-renamed.html")
        try fm.moveItem(at: page, to: moved)
        try await waitUntil { let urls = files(in: index.folders); return urls.contains(moved) && !urls.contains(page) }
        print("PASS: automatic refresh detects additions and moves without reopening the view")

        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: htmlDir.path)
        try await waitUntil { index.errorMessage != nil }
        precondition(!index.folders.isEmpty, "Read failure must preserve the previous successful list")
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: htmlDir.path)
        try await waitUntil { index.errorMessage == nil }
        monitor.cancel()
        await monitor.value
        print("PASS: read failures are visible, preserve results, and recover on the next scan")
        print("PASS: all library mount regression checks")
    }

    @MainActor
    static func files(in folders: [LibraryFolder]) -> [URL] {
        folders.flatMap { folder in
            folder.files.map(\.sourceURL) + files(in: folder.folders)
        }
    }

    @MainActor
    static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { preconditionFailure("Expected a value") }
        return value
    }

    @MainActor
    static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        preconditionFailure("Timed out waiting for the mount index to update")
    }
}
