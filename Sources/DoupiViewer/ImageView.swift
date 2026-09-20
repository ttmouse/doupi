import AppKit
import SwiftUI

/// Shared image cache to avoid repeated disk reads.
private let imageCache: NSCache<NSURL, NSImage> = {
    let cache = NSCache<NSURL, NSImage>()
    cache.countLimit = 64
    return cache
}()

/// Interactive image preview with zoom, pan, and viewport controls.
struct ImageView: View {
    let url: URL
    var reloadToken: Int = 0

    @State private var zoomScale: CGFloat = 1
    @State private var command: ImageCanvasCommand?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZoomableImageCanvas(url: url, reloadToken: reloadToken, zoomScale: $zoomScale, command: command)
                .background(Color.appBackground)

            HStack(spacing: 2) {
                controlButton("minus") { send(.zoomOut) }
                Text(zoomLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.appText)
                    .frame(minWidth: 48)
                controlButton("plus") { send(.zoomIn) }
                Divider().frame(height: 16)
                controlButton("arrow.down.right.and.arrow.up.left") { send(.fitToWindow) }
                    .help("适应窗口 (⌘0)")
                controlButton("1.magnifyingglass") { send(.actualSize) }
                    .help("实际大小")
                Divider().frame(height: 16)
                controlButton("folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .help("在访达中显示")
                controlButton("arrow.up.forward.app") {
                    NSWorkspace.shared.open(url)
                }
                .help("用默认程序打开")
            }
            .padding(5)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.appBorder.opacity(0.7), lineWidth: 0.5)
            )
            .padding(12)
        }
        .onAppear { send(.fitToWindow) }
        .onChange(of: url) { _, _ in send(.fitToWindow) }
    }

    private var zoomLabel: String {
        "\(Int((zoomScale * 100).rounded()))%"
    }

    private func controlButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.appText)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(icon == "minus" ? "缩小 (⌘-)" : icon == "plus" ? "放大 (⌘+)" : "")
    }

    private func send(_ operation: ImageCanvasCommand.Operation) {
        command = ImageCanvasCommand(operation: operation)
    }
}

private struct ImageCanvasCommand: Equatable {
    enum Operation {
        case zoomIn
        case zoomOut
        case fitToWindow
        case actualSize
    }

    let id = UUID()
    let operation: Operation

    static func == (lhs: ImageCanvasCommand, rhs: ImageCanvasCommand) -> Bool {
        lhs.id == rhs.id
    }
}

private struct ZoomableImageCanvas: NSViewRepresentable {
    let url: URL
    let reloadToken: Int
    @Binding var zoomScale: CGFloat
    let command: ImageCanvasCommand?

    func makeCoordinator() -> Coordinator {
        Coordinator(zoomScale: $zoomScale)
    }

    func makeNSView(context: Context) -> ZoomableImageCanvasView {
        let view = ZoomableImageCanvasView()
        view.onZoomChange = { scale in
            context.coordinator.updateZoom(scale)
        }
        view.loadImage(from: url)
        context.coordinator.loadedURL = url
        context.coordinator.loadedToken = reloadToken
        return view
    }

    func updateNSView(_ nsView: ZoomableImageCanvasView, context: Context) {
        if context.coordinator.loadedURL != url || context.coordinator.loadedToken != reloadToken {
            nsView.loadImage(from: url, forceReload: context.coordinator.loadedToken != reloadToken)
            context.coordinator.loadedURL = url
            context.coordinator.loadedToken = reloadToken
        }
        guard let command, context.coordinator.lastCommandID != command.id else { return }
        context.coordinator.lastCommandID = command.id
        nsView.perform(command.operation)
    }

    final class Coordinator {
        var zoomScale: Binding<CGFloat>
        var loadedURL: URL?
        var loadedToken = -1
        var lastCommandID: UUID?

        init(zoomScale: Binding<CGFloat>) {
            self.zoomScale = zoomScale
        }

        func updateZoom(_ scale: CGFloat) {
            let zoomScale = zoomScale
            DispatchQueue.main.async {
                guard abs(zoomScale.wrappedValue - scale) > 0.001 else { return }
                zoomScale.wrappedValue = scale
            }
        }
    }
}

private final class ZoomableImageCanvasView: NSView {
    private let minimumZoom: CGFloat = 0.05
    private let maximumZoom: CGFloat = 16
    private var image: NSImage?
    private var panOffset = CGPoint.zero
    private var dragOrigin: CGPoint?
    private var zoomScale: CGFloat = 1
    private var fitScale: CGFloat = 1
    private var isFitted = true
    private let imageView = NSImageView()

    var onZoomChange: ((CGFloat) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        layer?.backgroundColor = NSColor(Color.appBackground).cgColor
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.animates = true
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        let wasFitted = isFitted
        super.resize(withOldSuperviewSize: oldSize)
        if wasFitted { fitToWindow() }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        updateImageFrame()
    }

    func loadImage(from url: URL, forceReload: Bool = false) {
        let nsURL = url as NSURL
        if forceReload { imageCache.removeObject(forKey: nsURL) }
        if let cached = imageCache.object(forKey: nsURL) {
            image = cached
        } else if let loaded = NSImage(contentsOf: url) {
            imageCache.setObject(loaded, forKey: nsURL)
            image = loaded
        } else {
            image = nil
        }
        imageView.image = image
        imageView.isHidden = image == nil
        panOffset = .zero
        isFitted = true
        DispatchQueue.main.async { [weak self] in self?.fitToWindow() }
        needsDisplay = true
    }

    func perform(_ operation: ImageCanvasCommand.Operation) {
        switch operation {
        case .zoomIn:
            setZoom(zoomScale * 1.25)
        case .zoomOut:
            setZoom(zoomScale / 1.25)
        case .fitToWindow:
            fitToWindow()
        case .actualSize:
            panOffset = .zero
            setZoom(1)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(Color.appBackground).setFill()
        bounds.fill()

        guard image != nil else {
            drawPlaceholder()
            return
        }

        updateImageFrame()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            fitToWindow()
            return
        }
        dragOrigin = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin else { return }
        let location = event.locationInWindow
        panOffset.x += location.x - dragOrigin.x
        panOffset.y += location.y - dragOrigin.y
        self.dragOrigin = location
        isFitted = false
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
    }

    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) {
            panOffset.x += event.scrollingDeltaX
            panOffset.y -= event.scrollingDeltaY
            isFitted = false
            needsDisplay = true
        } else {
            setZoom(zoomScale * (event.scrollingDeltaY > 0 ? 1.1 : 0.9))
        }
    }

    override func magnify(with event: NSEvent) {
        setZoom(zoomScale * (1 + event.magnification))
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.keyDown(with: event)
            return
        }
        switch event.charactersIgnoringModifiers {
        case "+", "=": setZoom(zoomScale * 1.25)
        case "-": setZoom(zoomScale / 1.25)
        case "0": fitToWindow()
        default: super.keyDown(with: event)
        }
    }

    private func fitToWindow() {
        guard let image, image.size.width > 0, image.size.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        let horizontal = max((bounds.width - 48) / image.size.width, minimumZoom)
        let vertical = max((bounds.height - 48) / image.size.height, minimumZoom)
        fitScale = min(horizontal, vertical, 1)
        panOffset = .zero
        isFitted = true
        setZoom(fitScale, preservesFittedState: true)
    }

    private func setZoom(_ scale: CGFloat, preservesFittedState: Bool = false) {
        zoomScale = min(max(scale, minimumZoom), maximumZoom)
        if !preservesFittedState {
            isFitted = abs(zoomScale - fitScale) < 0.001
        }
        onZoomChange?(zoomScale)
        needsDisplay = true
    }

    private func updateImageFrame() {
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let size = NSSize(width: image.size.width * zoomScale, height: image.size.height * zoomScale)
        imageView.frame = NSRect(
            x: (bounds.width - size.width) / 2 + panOffset.x,
            y: (bounds.height - size.height) / 2 + panOffset.y,
            width: size.width,
            height: size.height
        )
    }

    private func drawPlaceholder() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor(Color.appMuted),
            .paragraphStyle: paragraph,
        ]
        let text = "无法读取图片"
        text.draw(in: NSRect(x: 0, y: bounds.midY - 10, width: bounds.width, height: 20), withAttributes: attributes)
    }
}
