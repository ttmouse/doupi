import Foundation
import Darwin

/// A cheap identity for a file, used to ignore directory events unrelated to the open file.
/// The inode catches atomic replace operations; size and modification date catch in-place writes.
struct FileSnapshot: Equatable, Sendable {
    let exists: Bool
    let size: Int64
    let modificationDate: Date?
    let fileNumber: UInt64?

    static func capture(_ url: URL) -> Self {
        let path = url.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            return Self(exists: false, size: 0, modificationDate: nil, fileNumber: nil)
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = attributes?[.modificationDate] as? Date
        let fileNumber = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
        return Self(
            exists: true,
            size: size,
            modificationDate: modificationDate,
            fileNumber: fileNumber
        )
    }

    static func didChange(from old: Self, to new: Self) -> Bool {
        old != new
    }
}

/// Watches the containing directory rather than the file itself, so an editor's
/// write-to-temp-and-rename save is observed too. Directory events are debounced
/// and compared against a file snapshot to avoid rebuilding for unrelated files.
final class FileChangeMonitor {
    let url: URL

    private let directoryURL: URL
    private let onChange: (URL) -> Void
    private let queue = DispatchQueue(label: "com.doupi.file-change-monitor", qos: .utility)
    private let queueKey = DispatchSpecificKey<Void>()
    private var source: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var lastSnapshot: FileSnapshot
    private var pendingCheck: DispatchWorkItem?
    private var stopped = false
    private var generation = 0

    init(url: URL, onChange: @escaping (URL) -> Void = { url in
        NotificationCenter.default.post(name: .doupiFileChanged, object: url)
    }) {
        self.url = url.standardizedFileURL
        self.directoryURL = self.url.deletingLastPathComponent()
        self.onChange = onChange
        self.lastSnapshot = FileSnapshot.capture(self.url)
        queue.setSpecific(key: queueKey, value: ())
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.stopped, self.source == nil else { return }
            let descriptor = open(self.directoryURL.path, O_EVTONLY)
            guard descriptor >= 0 else { return }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .link, .rename, .delete, .revoke],
                queue: self.queue
            )
            source.setEventHandler { [weak self] in
                self?.scheduleCheck()
            }
            source.setCancelHandler {
                close(descriptor)
            }
            self.source = source
            source.resume()

            // Directory vnode events do not reliably report in-place writes on macOS.
            // Watch the file inode as well; the directory watcher remains responsible for
            // atomic replace/delete/recreate, where the inode itself changes.
            if let fileSource = self.makeFileSource() {
                self.fileSource = fileSource
                fileSource.resume()
            }
        }
    }

    private func makeFileSource() -> DispatchSourceFileSystemObject? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleCheck()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        return source
    }

    func stop() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopOnQueue()
        } else {
            queue.sync { stopOnQueue() }
        }
    }

    private func stopOnQueue() {
        guard !stopped else { return }
        stopped = true
        generation &+= 1
        pendingCheck?.cancel()
        pendingCheck = nil
        source?.cancel()
        source = nil
        fileSource?.cancel()
        fileSource = nil
    }

    deinit {
        stop()
    }

    private func scheduleCheck() {
        guard !stopped else { return }
        pendingCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in
            self?.checkForChange()
        }
        pendingCheck = check
        queue.asyncAfter(deadline: .now() + .milliseconds(150), execute: check)
    }

    private func checkForChange() {
        guard !stopped else { return }
        let next = FileSnapshot.capture(url)
        guard FileSnapshot.didChange(from: lastSnapshot, to: next) else { return }
        lastSnapshot = next

        let url = self.url
        let onChange = self.onChange
        let generation = self.generation
        DispatchQueue.main.async { [weak self] in
            // A check can already be queued when the user closes the document or switches files.
            // Do not deliver that stale event to a later monitor for the same path.
            guard let self, self.isActive(generation) else { return }
            onChange(url)
        }
    }

    private func isActive(_ expectedGeneration: Int) -> Bool {
        queue.sync { !stopped && generation == expectedGeneration }
    }
}

extension Notification.Name {
    static let doupiFileChanged = Notification.Name("DoupiFileChanged")
}
