import Foundation

/// Drives search bar visibility and state across the app.
/// Plain struct so @State can track any property mutation directly.
struct SearchState {
    var isVisible = false
    var query = ""
    var matchCount = 0
    var currentMatch = 0

    /// Set by navigateSearch to tell views which direction to go.
    var pendingAction: SearchAction? = nil

    /// Resets everything when search is closed.
    mutating func close() {
        isVisible = false
        query = ""
        matchCount = 0
        currentMatch = 0
        pendingAction = nil
    }
}
