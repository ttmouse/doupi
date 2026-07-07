import AppKit
import SwiftUI

/// Entry point for Doupi Viewer.
@main
struct DoupiApp: App {
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .frame(minWidth: 720, minHeight: 400)
                .windowHidesTitlebar()
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}

// MARK: - Window configuration view modifier

private struct WindowTitlebarHider: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(WindowAccessor())
    }
}

private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func configure(_ window: NSWindow) {
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false
        window.backgroundColor = NSColor(red: 0.91, green: 0.90, blue: 0.88, alpha: 1.0)
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unified
    }
}

extension View {
    func windowHidesTitlebar() -> some View {
        modifier(WindowTitlebarHider())
    }
}
