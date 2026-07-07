import Foundation

/// JS string escaping utilities.
extension String {
    /// Escape the string for safe embedding in a JS single-quoted string literal.
    func escapedForJS() -> String {
        self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
