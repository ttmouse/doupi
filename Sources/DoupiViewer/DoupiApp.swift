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
                installDragHandle(on: window)
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

    /// Installs an invisible 24pt drag strip at the top of the window.
    ///
    /// Uses an NSEvent monitor to intercept leftMouseDown in the top zone
    /// **before** any view's hitTest runs (WKWebView cannot block it).
    /// The event is then forwarded to a dedicated NSView whose `mouseDown`
    /// calls the native `performDrag(with:)` for smooth window dragging.
    private func installDragHandle(on window: NSWindow) {
        guard let contentView = window.contentView else { return }

        // Thin subview that receives the forwarded event and calls performDrag.
        // Also provides cursor feedback via tracking areas.
        let dragView = WindowDragView(
            frame: NSRect(x: 0,
                          y: contentView.bounds.height - 24,
                          width: contentView.bounds.width,
                          height: 24)
        )
        dragView.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(dragView)

        // Event monitor — fires before hitTest, so WKWebView never sees the event.
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard event.window == window,
                  let cv = window.contentView,
                  event.locationInWindow.y >= cv.bounds.height - 24
            else { return event }

            // Forward to our drag view so the native performDrag handles the
            // entire drag natively (smooth, no jitter).
            if let dv = cv.subviews.first(where: { $0 is WindowDragView }) {
                dv.mouseDown(with: event)
            }

            return nil  // prevent dispatch to WKWebView / other views
        }

        // Keep the monitor alive by associating it with the window.
        objc_setAssociatedObject(
            window,
            &dragMonitorKey,
            monitor,
            .OBJC_ASSOCIATION_RETAIN
        )
    }
}

// MARK: - Private helpers

private var dragMonitorKey: UInt8 = 0

/// Transparent NSView that uses `performDrag(with:)` for native smooth window
/// dragging, and shows `openHand` cursor on hover.
private final class WindowDragView: NSView {

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Drag (called from the event monitor)

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    // MARK: - Cursor feedback

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.openHand.push()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
    }
}

extension View {
    func windowHidesTitlebar() -> some View {
        modifier(WindowTitlebarHider())
    }
}
