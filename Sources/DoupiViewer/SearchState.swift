import Foundation
import Observation

/// Drives search bar visibility and state across the app.
@Observable
class SearchState {
    var isVisible = false
    var query = ""
    var matchCount = 0
    var currentMatch = 0

    /// Set by navigateSearch to tell views which direction to go.
    var pendingAction: SearchAction? = nil

    /// Resets everything when search is closed.
    func close() {
        isVisible = false
        query = ""
        matchCount = 0
        currentMatch = 0
        pendingAction = nil
    }
}
