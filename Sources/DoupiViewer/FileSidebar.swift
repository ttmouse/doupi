import SwiftUI
import UniformTypeIdentifiers

// MARK: - File Format Enum

/// Document format categories for the sidebar filter.
enum FileFormat: String, CaseIterable, Hashable {
    case html = "HTML"
    case markdown = "Markdown"
    case code = "Code"
    case image = "Image"
    case pdf = "PDF"
    case text = "Text"
    case tsx = "TSX/JSX"

    var icon: String {
        switch self {
        case .html:     return "globe"
        case .markdown: return "doc.text"
        case .code:     return "chevron.left.forwardslash.chevron.right"
        case .image:    return "photo"
        case .pdf:      return "doc.richtext"
        case .text:     return "doc.plaintext"
        case .tsx:      return "curlybraces"
        }
    }
    static func `for`(_ url: URL) -> FileFormat? {
        let ext = url.pathExtension.lowercased()
        if FileInfo.isHTML(ext: ext) { return .html }
        if FileInfo.isMarkdown(ext: ext) { return .markdown }
        if FileInfo.isTSX(ext: ext) { return .tsx }
        if FileInfo.isPDF(ext: ext) { return .pdf }
        if FileInfo.isText(ext: ext) { return .text }
        if FileInfo.isImage(ext: ext) { return .image }
        // code — only after checking tsx/jsx/html/md so those take priority
        if FileInfo.isCode(ext: ext) { return .code }
        return nil
    }
}

/// Sidebar with recent files history.
struct FileSidebar: View {

    @Binding var selectedURL: URL?
    var refreshToken: Int = 0
    @State private var recentFiles: [URL] = []
    @State private var filterText = ""
    @State private var selectedFormat: FileFormat? = nil
    @State private var isDropTargeted = false
    @FocusState private var isFilterFocused: Bool
    @State private var keyboardFocusIndex: Int? = nil
    @State private var selectedTag: String? = nil
    @State private var tagVersion = UUID()
    @State private var showNewTagAlert = false
    @State private var newTagName = ""
    @State private var pendingTagURL: URL? = nil
    @State private var pinnedURLs: Set<URL> = []
    @State private var isSidebarHovered = false
    @State private var isFormatFilterExpanded = true
    @State private var isTagFilterExpanded = true
    @State private var isFormatHeaderHovered = false
    @State private var isTagHeaderHovered = false

    /// External binding to focus filter from ContentView keyboard shortcut.
    var focusFilter: Binding<Bool>?

    private var filteredFiles: [URL] {
        var files = recentFiles

        // Text filter
        if !filterText.isEmpty {
            files = files.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(filterText) }
        }

        // Format filter
        if let fmt = selectedFormat {
            files = files.filter { url in
                guard let fileFmt = FileFormat.for(url) else { return false }
                return fileFmt == fmt
            }
        }

        // Tag filter
        if let tag = selectedTag {
            let tagged = Set(FileTags.urls(for: tag).map(\.standardizedFileURL))
            files = files.filter { tagged.contains($0.standardizedFileURL) }
        }

        // Pinned items first
        files.sort { a, b in
            let aPinned = pinnedURLs.contains(a.standardizedFileURL)
            let bPinned = pinnedURLs.contains(b.standardizedFileURL)
            if aPinned != bPinned { return aPinned }
            return false
        }

        return files
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter input
            if !recentFiles.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.appMuted)
                    TextField("筛选文件...", text: $filterText)
                        .font(.system(size: 12))
                        .foregroundColor(.appText)
                        .textFieldStyle(.plain)
                        .focused($isFilterFocused)
                        .onKeyPress(phases: .down) { press in
                            let list = filteredFiles
                            guard !list.isEmpty else { return .ignored }
                            switch press.key {
                            case .downArrow:
                                if let idx = keyboardFocusIndex {
                                    keyboardFocusIndex = min(idx + 1, list.count - 1)
                                } else {
                                    keyboardFocusIndex = 0
                                }
                                return .handled
                            case .upArrow:
                                if let idx = keyboardFocusIndex {
                                    keyboardFocusIndex = max(idx - 1, 0)
                                } else {
                                    keyboardFocusIndex = list.count - 1
                                }
                                return .handled
                            case .return:
                                if let idx = keyboardFocusIndex, idx < list.count {
                                    selectedURL = list[idx]
                                }
                                return .handled
                            default:
                                return .ignored
                            }
                        }
                    if !filterText.isEmpty {
                        Button(action: { filterText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.appMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.appBorder, lineWidth: 0.5)
                )
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }

            // Format filter area
            if !recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Button(action: { isFormatFilterExpanded.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: isFormatFilterExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.appMuted)
                                .frame(width: 8)
                            Text("格式筛选")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.appMuted)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isFormatHeaderHovered ? Color.appHoverBg : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isFormatHeaderHovered = hovering
                    }

                    if isFormatFilterExpanded {
                        FormatRow(
                            label: "全部",
                            icon: "line.horizontal.3.decrease.circle",
                            count: recentFiles.count,
                            isSelected: selectedFormat == nil
                        ) {
                            selectedFormat = nil
                        }

                        ForEach(FileFormat.allCases, id: \.self) { format in
                            let count = recentFiles.filter { url in
                                guard let fmt = FileFormat.for(url) else { return false }
                                return fmt == format
                            }.count

                            if count > 0 {
                                FormatRow(
                                    label: format.rawValue,
                                    icon: format.icon,
                                    count: count,
                                    isSelected: selectedFormat == format
                                ) {
                                    if selectedFormat == format {
                                        selectedFormat = nil
                                    } else {
                                        selectedFormat = format
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
            }

            // Tag filter area
            if !recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Button(action: { isTagFilterExpanded.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: isTagFilterExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.appMuted)
                                .frame(width: 8)
                            Text("标签筛选")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.appMuted)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(isTagHeaderHovered ? Color.appHoverBg : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isTagHeaderHovered = hovering
                    }

                    if isTagFilterExpanded {
                        TagRow(
                            label: "全部",
                            count: recentFiles.count,
                            isSelected: selectedTag == nil,
                            action: { selectedTag = nil }
                        )

                        let allTags = FileTags.allTags()

                        ForEach(allTags, id: \.self) { tag in
                            let count = recentFiles.filter { url in
                                FileTags.tags(for: url).contains(tag)
                            }.count

                            if count > 0 {
                                TagRow(
                                    label: tag,
                                    count: count,
                                    isSelected: selectedTag == tag,
                                    action: {
                                        if selectedTag == tag {
                                            selectedTag = nil
                                        } else {
                                            selectedTag = tag
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
                .id(tagVersion)
            }

            Rectangle()
                .fill(Color.appBorder)
                .frame(height: 0.5)
                .padding(.bottom, 4)

            if !recentFiles.isEmpty {
                if filteredFiles.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(.appMuted)
                        Text("无匹配的文件")
                            .font(.system(size: 12))
                            .foregroundColor(.appMuted)
                    }
                    Spacer()
                } else {
                    SidebarScrollView(content: VStack(spacing: 0) {
                    ForEach(Array(filteredFiles.enumerated()), id: \.offset) { idx, url in
                        SidebarRow(
                            url: url,
                            isSelected: selectedURL == url,
                            isKeyboardFocused: idx == keyboardFocusIndex,
                            isPinned: pinnedURLs.contains(url.standardizedFileURL),
                            onTogglePin: { togglePin(url) },
                            onClearKeyboardFocus: { keyboardFocusIndex = nil },
                            action: { selectedURL = url }
                        )
                        .contextMenu {
                            if !FileTags.allTags().isEmpty {
                                Menu("打标") {
                                    ForEach(FileTags.allTags(), id: \.self) { tag in
                                        let tagged = FileTags.tags(for: url).contains(tag)
                                        Button {
                                            FileTags.toggleTag(tag, for: url)
                                            tagVersion = UUID()
                                        } label: {
                                            HStack {
                                                Text(tag)
                                                if tagged {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                }
                                Divider()
                            }
                            Button("新建标签...") {
                                pendingTagURL = url
                                newTagName = ""
                                showNewTagAlert = true
                            }
                            Divider()
                            Button(pinnedURLs.contains(url.standardizedFileURL) ? "取消置顶" : "置顶") {
                                togglePin(url)
                            }
                            Divider()
                            Button("移除") {
                                removeFromRecent(url)
                            }
                        }
                    }
                }, isHovered: isSidebarHovered)
                }
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(.appMuted)
                    Text("打开文件即可在此看到记录")
                        .font(.system(size: 12))
                        .foregroundColor(.appMuted)
                }
                Spacer()
            }
        }
        .background(isDropTargeted ? Color.appAccent.opacity(0.08) : Color.appInfoBg)
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(isDropTargeted ? Color.appAccent : Color.clear, lineWidth: 0.5)
        )
        .onHover { hovering in
            isSidebarHovered = hovering
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .frame(minWidth: 200)
        .onAppear {
            recentFiles = FileHistory.load()
            pinnedURLs = PinnedFiles.load()
        }
        .onChange(of: refreshToken) { _, _ in
            recentFiles = FileHistory.load()
            pinnedURLs = PinnedFiles.load()
        }
        .onChange(of: filterText) { _, _ in
            keyboardFocusIndex = nil
        }
        .onChange(of: focusFilter?.wrappedValue) { _, focused in
            if focused == true {
                isFilterFocused = true
                focusFilter?.wrappedValue = false
            }
        }
        .alert("新建标签", isPresented: $showNewTagAlert) {
            TextField("标签名称", text: $newTagName)
            Button("取消", role: .cancel) { }
            Button("创建") {
                let tag = newTagName.trimmingCharacters(in: .whitespaces)
                guard !tag.isEmpty else { return }
                if let url = pendingTagURL {
                    FileTags.addTag(tag, to: url)
                }
                tagVersion = UUID()
                pendingTagURL = nil
            }
        } message: {
            Text("输入新标签名称")
        }
    }

    // MARK: - Helpers

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task {
            let urls = await FileDropDelegate.collectRenderableFiles(from: providers)
            guard !urls.isEmpty else { return }
            FileHistory.bulkAdd(urls)
            await MainActor.run {
                recentFiles = FileHistory.load()
                selectedURL = urls[0]
            }
        }
        return true
    }

    private func togglePin(_ url: URL) {
        PinnedFiles.toggle(url)
        pinnedURLs = PinnedFiles.load()
    }

    private func removeFromRecent(_ url: URL) {
        var urls = FileHistory.load()
        urls.removeAll { $0 == url }
        FileHistory.save(urls)
        recentFiles = urls
        if selectedURL == url { selectedURL = nil }
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let url: URL
    let isSelected: Bool
    let isKeyboardFocused: Bool
    let isPinned: Bool
    let onTogglePin: () -> Void
    let onClearKeyboardFocus: () -> Void
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .imageScale(.small)
                .foregroundColor(isSelected ? .appAccent : .appMuted)
                .frame(width: 18)

            Text(url.lastPathComponent)
                .font(.system(size: 13))
                .foregroundColor(.appText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isPinned ? .appAccent : .appMuted)
            }
            .buttonStyle(.plain)
            .opacity(isPinned || isHovering ? 1 : 0)
            .scaleEffect(isPinned || isHovering ? 1 : 0.85, anchor: .trailing)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(rowBackground)
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onClearKeyboardFocus()
            action()
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
            if hovering {
                onClearKeyboardFocus()
            }
        }
    }

    private var rowBackground: Color {
        if isSelected { return .appSelectedBg }
        if isHovering || isKeyboardFocused { return .appHoverBg }
        return .clear
    }

    private var iconName: String {
        switch url.pathExtension.lowercased() {
        case "html", "htm":  return "globe"
        case "swift":        return "swift"
        case "pdf":          return "doc.richtext"
        case "js", "ts", "tsx", "jsx": return "chevron.left.forwardslash.chevron.right"
        case "css", "scss", "less":  return "paintbrush"
        case "json":         return "curlybraces"
        case "md", "markdown": return "doc.text"
        case "png", "jpg", "jpeg", "gif", "webp": return "photo"
        case "yaml", "yml", "toml": return "gearshape"
        case "py":           return "play.rectangle"
        case "sh", "bash", "zsh": return "terminal"
        case "sql":          return "tablecells"
        default:             return "doc"
        }
    }
}

// MARK: - Format Row

/// Vertical filter row in the format filter area.
private struct FormatRow: View {
    let label: String
    let icon: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .appAccent : .appMuted)
                .frame(width: 18)

            Text(label)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .appAccent : .appText)

            Spacer(minLength: 0)

            Text("\(count)")
                .font(.system(size: 11))
                .foregroundColor(.appMuted)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(rowBackground)
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var rowBackground: Color {
        if isSelected { return Color.appAccentDimmed }
        if isHovering { return Color.black.opacity(0.03) }
        return .clear
    }
}

// MARK: - Tag Row

/// Vertical filter row in the tag filter area.
private struct TagRow: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .appAccent : .appMuted)
                .frame(width: 18)

            Text(label)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .appAccent : .appText)

            Spacer(minLength: 0)

            Text("\(count)")
                .font(.system(size: 11))
                .foregroundColor(.appMuted)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(rowBackground)
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var rowBackground: Color {
        if isSelected { return Color.appAccentDimmed }
        if isHovering { return Color.black.opacity(0.03) }
        return .clear
    }
}

// MARK: - Sidebar Scroll View

/// Width of the custom scrollbar indicator.
private let sidebarScrollerWidth: CGFloat = 4

/// AppKit-backed NSScrollView that replaces SwiftUI ScrollView for the sidebar
/// file list.  Uses a hand-drawn 2 px overlay indicator instead of NSScroller
/// so the system's private overlay animations can't fight our alpha control.
private struct SidebarScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    let isHovered: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.scrollerStyle = .overlay
        sv.drawsBackground = false
        sv.hasVerticalScroller = false   // native scroller hidden
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = false
        sv.postsBoundsChangedNotifications = true

        // Custom scrollbar indicator — a thin rounded pill
        let indicator = NSView()
        indicator.wantsLayer = true
        indicator.layer?.backgroundColor = NSColor(white: 0, alpha: 0.22).cgColor
        indicator.layer?.cornerRadius = sidebarScrollerWidth / 2
        indicator.alphaValue = 0
        sv.addSubview(indicator)
        context.coordinator.indicator = indicator

        // Host SwiftUI content inside the scroll view
        let host = NSHostingView(rootView: content)
        host.translatesAutoresizingMaskIntoConstraints = false
        sv.documentView = host

        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: sv.contentView.topAnchor),
            host.leadingAnchor.constraint(equalTo: sv.contentView.leadingAnchor),
            host.widthAnchor.constraint(equalTo: sv.contentView.widthAnchor),
        ])

        context.coordinator.scrollView = sv
        context.coordinator.subscribe()
        return sv
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let host = nsView.documentView as? NSHostingView<Content> {
            host.rootView = content
        }
        context.coordinator.setVisible(isHovered)
        // Content change may shift scroll offset — refresh indicator position
        DispatchQueue.main.async {
            context.coordinator.layoutIndicator()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        weak var scrollView: NSScrollView?
        var indicator: NSView?

        func subscribe() {
            guard let sv = scrollView else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(contentOrBoundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: sv.contentView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(contentOrBoundsDidChange),
                name: NSView.frameDidChangeNotification,
                object: sv.documentView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(contentOrBoundsDidChange),
                name: NSScrollView.didLiveScrollNotification,
                object: sv
            )
        }

        func setVisible(_ visible: Bool) {
            let alpha: CGFloat = visible ? 1 : 0
            guard indicator?.alphaValue != alpha else { return }
            // System can't override because this is our own view
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = visible ? 0.15 : 0.3
                indicator?.animator().alphaValue = alpha
            }
            if visible { layoutIndicator() }
        }

        @objc func contentOrBoundsDidChange() {
            layoutIndicator()
        }

        /// Position the custom indicator based on current scroll state.
        func layoutIndicator() {
            guard let sv = scrollView, let indicator = indicator,
                  let docView = sv.documentView else { return }

            let contentHeight = docView.frame.height
            let visibleHeight = sv.contentView.bounds.height
            let scrollOffset = sv.contentView.bounds.origin.y

            guard contentHeight > visibleHeight, contentHeight > 0 else {
                indicator.isHidden = true
                return
            }
            indicator.isHidden = false

            let margin: CGFloat = 2
            let svHeight = sv.bounds.height
            let trackLen = svHeight - margin * 2
            let knobHeight = max((visibleHeight / contentHeight) * trackLen, 8)
            let maxScroll = contentHeight - visibleHeight
            let progress = maxScroll > 0 ? scrollOffset / maxScroll : 0

            // NSScrollView is non-flipped: y=0 at bottom, y=svHeight at top
            let minY = margin
            let knobY = minY + progress * (trackLen - knobHeight)

            indicator.frame = NSRect(
                x: sv.bounds.width - sidebarScrollerWidth - 3,
                y: knobY,
                width: sidebarScrollerWidth,
                height: knobHeight
            )
        }
    }
}
