import Foundation

@main
struct FileChangeCheck {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("doupi-file-change-\(UUID().uuidString)")
        let file = directory.appendingPathComponent("document.md")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data(repeating: 0x41, count: 8).write(to: file)
        let original = FileSnapshot.capture(file)
        expect(original.exists, "initial file exists")
        expect(!FileSnapshot.didChange(from: original, to: FileSnapshot.capture(file)), "unchanged file is ignored")

        try Data(repeating: 0x42, count: 16).write(to: file)
        let rewritten = FileSnapshot.capture(file)
        expect(FileSnapshot.didChange(from: original, to: rewritten), "in-place rewrite is detected")

        let replacement = directory.appendingPathComponent("replacement")
        try Data(repeating: 0x43, count: 16).write(to: replacement)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: replacement)
        let replaced = FileSnapshot.capture(file)
        expect(FileSnapshot.didChange(from: rewritten, to: replaced), "atomic replacement is detected")

        try FileManager.default.removeItem(at: file)
        let deleted = FileSnapshot.capture(file)
        expect(!deleted.exists, "deletion is visible")
        expect(FileSnapshot.didChange(from: replaced, to: deleted), "deletion is detected")
        expect(!FileSnapshot.didChange(from: deleted, to: FileSnapshot.capture(file)), "repeated missing state is ignored")

        checkLiveMonitor(in: directory, file: file)
        print("PASS: file rewrite, atomic replacement, deletion, and duplicate suppression")
    }

    private static func checkLiveMonitor(in directory: URL, file: URL) {
        // This exercises the real directory event source, not only the snapshot comparison above.
        // In particular, a directory watcher must survive an atomic replace and a delete/recreate.
        try? Data(repeating: 0x51, count: 11).write(to: file)
        let unrelated = directory.appendingPathComponent("unrelated.txt")
        var events: [URL] = []
        let monitor = FileChangeMonitor(url: file) { url in events.append(url) }
        monitor.start()
        monitor.start() // Starting twice must not create two watchers.
        pump(0.2)

        try! Data(repeating: 0x52, count: 22).write(to: file)
        expect(waitUntil(timeout: 2) { events.count >= 1 }, "live monitor reports in-place rewrite")
        let afterRewrite = events.count

        try! Data(repeating: 0x53, count: 33).write(to: unrelated)
        pump(0.4)
        expect(events.count == afterRewrite, "live monitor ignores unrelated files")

        let replacement = directory.appendingPathComponent("live-replacement")
        try! Data(repeating: 0x54, count: 44).write(to: replacement)
        _ = try! FileManager.default.replaceItemAt(file, withItemAt: replacement)
        expect(waitUntil(timeout: 2) { events.count > afterRewrite }, "live monitor reports atomic replacement")
        let afterReplacement = events.count

        try! FileManager.default.removeItem(at: file)
        expect(waitUntil(timeout: 2) { events.count > afterReplacement }, "live monitor reports deletion")
        let afterDeletion = events.count

        try! Data(repeating: 0x55, count: 55).write(to: file)
        expect(waitUntil(timeout: 2) { events.count > afterDeletion }, "live monitor survives delete and reports recreation")

        monitor.stop()
        let afterStop = events.count
        try! Data(repeating: 0x56, count: 66).write(to: file)
        pump(0.4)
        expect(events.count == afterStop, "stopped monitor delivers no further events")
    }

    private static func waitUntil(timeout: Double, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    private static func pump(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
        print("PASS: \(message)")
    }
}
