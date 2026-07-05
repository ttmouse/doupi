import Foundation
import Observation

/// Shared logger for JS console messages from WKWebView.
/// Displayed in the sidebar console panel.
@Observable
final class ConsoleLogger {
    static let shared = ConsoleLogger()

    var entries: [Entry] = []
    private let maxEntries = 200

    struct Entry: Identifiable {
        let id = UUID()
        let level: String   // "log", "warn", "error"
        let message: String
        let timestamp: Date
    }

    private init() {}

    func add(level: String, message: String) {
        let entry = Entry(level: level, message: message, timestamp: Date())
        DispatchQueue.main.async {
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.entries.removeAll()
        }
    }
}
