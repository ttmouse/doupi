import AppKit
import SwiftUI

/// Entry point for Doupi Viewer.
@main
struct DoupiApp: App {
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .frame(minWidth: 720, minHeight: 400)
                .onAppear {
                    guard let window = NSApplication.shared.windows.first(where: {
                        $0.identifier?.rawValue == "main"
                    }) ?? NSApplication.shared.mainWindow else { return }

                    window.titlebarAppearsTransparent = true
                    window.isOpaque = false
                    window.backgroundColor = NSColor(red: 0.91, green: 0.90, blue: 0.88, alpha: 1.0)
                    window.styleMask.insert(.fullSizeContentView)
                    window.toolbarStyle = .unified
                }
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}
