import Foundation

/// Persists the sidebar's expanded sections and collapsed library folders.
struct SidebarExpansionState: Codable, Equatable {
    var isFormatFilterExpanded = true
    var isTagFilterExpanded = true
    var isPinnedExpanded = true
    var isLibraryExpanded = true
    var isRecentExpanded = true
    var collapsedFolderIDs: Set<UUID> = []
}

enum SidebarExpansionStore {
    private static let key = "DoupiSidebarExpansionState"

    static func load() -> SidebarExpansionState {
        guard let data = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(SidebarExpansionState.self, from: data)
        else { return SidebarExpansionState() }
        return state
    }

    static func save(_ state: SidebarExpansionState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
