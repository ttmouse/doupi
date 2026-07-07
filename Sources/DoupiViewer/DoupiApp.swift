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

    /// Adds an invisible 24pt strip at the top of the window's content area
    /// that handles window dragging via performDrag(with:).
    ///
    /// Uses two mechanisms so dragging works even when child views (e.g. WKWebView)
    /// cover the drag strip:
    ///  1. An NSView subview kept on top of the layer hierarchy (cursor + autoresize).
    ///  2. An NSEvent monitor that catches leftMouseDown in the top zone regardless
    ///     of which view is hit-tested first.
    private func installDragHandle(on window: NSWindow) {
        guard let contentView = window.contentView else { return }

        // 1. Invisible subview for cursor tracking and autoresizing.
        let dragView = WindowDragView(
            frame: NSRect(x: 0,
                          y: contentView.bounds.height - 24,
                          width: contentView.bounds.width,
                          height: 24)
        )
        dragView.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(dragView)

        // 2. Event monitor — fires before any view's hitTest.
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard event.window == window,
                  let cv = window.contentView,
                  event.locationInWindow.y >= cv.bounds.height - 24
            else { return event }
            window.performDrag(with: event)
            return nil
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

/// Key used to associate the event monitor with the window.
private var dragMonitorKey: UInt8 = 0

// MARK: - Drag handle NSView

/// A transparent NSView that initiates window dragging on mouseDown.
private final class WindowDragView: NSView {

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Layer-backed so it stays visually on top.
        wantsLayer = true
        layer?.backgroundColor = nil  // fully transparent
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var mouseDownCanMoveWindow: Bool { false }

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
