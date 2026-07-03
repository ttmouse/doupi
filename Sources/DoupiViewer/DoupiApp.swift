import SwiftUI

/// Entry point for Doupi Viewer.
@main
struct DoupiApp: App {
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .frame(minWidth: 720, minHeight: 400)
        }
        .windowResizability(.contentMinSize)
    }
}
