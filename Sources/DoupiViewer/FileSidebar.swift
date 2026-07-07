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
        if ["html", "htm"].contains(ext) { return .html }
        if ["md", "markdown"].contains(ext) { return .markdown }
        if ["tsx", "jsx"].contains(ext) { return .tsx }
        if ["pdf"].contains(ext) { return .pdf }
        if ["txt"].contains(ext) { return .text }
        if ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tiff", "tif", "ico"].contains(ext) { return .image }
        // code — only after checking tsx/jsx and html/md so those take priority
        let codeExts: Set<String> = [
            "js", "ts", "css", "scss", "less", "json", "yaml", "yml",
            "py", "go", "rs", "sql", "sh", "bash", "zsh", "toml", "xml",
            "php", "rb", "java", "c", "cpp", "h", "hpp", "swift", "kt",
            "scala", "pl", "lua", "r", "dart", "fs", "fsx", "svelte",
            "vue", "astro", "mjs", "cjs", "mts", "cts",
        ]
        if codeExts.contains(ext) { return .code }
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
    @State private var keyboardFocusIndex: Int = 0
    @State private var selectedTag: String? = nil
    @State private var tagVersion = UUID()
    @State private var showNewTagAlert = false
    @State private var newTagName = ""
    @State private var pendingTagURL: URL? = nil
    @State private var isSidebarHovered = false

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
                                if keyboardFocusIndex < list.count - 1 {
                                    keyboardFocusIndex += 1
                                }
                                return .handled
                            case .upArrow:
                                if keyboardFocusIndex > 0 {
                                    keyboardFocusIndex -= 1
                                }
                                return .handled
                            case .return:
                                let idx = min(keyboardFocusIndex, list.count - 1)
                                selectedURL = list[idx]
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
                    Text("格式筛选")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.appMuted)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

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
                .padding(.bottom, 4)
            }

            // Tag filter area
            if !recentFiles.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("标签筛选")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.appMuted)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 4)

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
                .padding(.bottom, 4)
                .id(tagVersion)
            }

            Divider()
                .overlay(Color.appBorder)
                .padding(.bottom, 4)

            if !recentFiles.isEmpty {
                SidebarScrollView(content: VStack(spacing: 0) {
                    ForEach(Array(filteredFiles.enumerated()), id: \.offset) { idx, url in
                        SidebarRow(url: url, isSelected: selectedURL == url, isKeyboardFocused: idx == keyboardFocusIndex) {
                            selectedURL = url
                        }
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
                            Button("移除") {
                                removeFromRecent(url)
                            }
                        }
                    }
                }, isHovered: isSidebarHovered)
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
                .strokeBorder(isDropTargeted ? Color.appAccent : Color.clear, lineWidth: 2)
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
        }
        .onChange(of: refreshToken) { _, _ in
            recentFiles = FileHistory.load()
        }
        .onChange(of: filterText) { _, _ in
            keyboardFocusIndex = 0
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
        }
        .padding(.vertical, 5)
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
        if isSelected { return .appSelectedBg }
        if isKeyboardFocused { return .appHoverBg }
        if isHovering { return .appHoverBg.opacity(0.6) }
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
        .padding(.vertical, 4)
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
        .padding(.vertical, 4)
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

/// Thin scroller width (≈ 2 px).
private let sidebarScrollerWidth: CGFloat = 2

/// AppKit-backed NSScrollView that replaces SwiftUI ScrollView for the sidebar
/// file list — gives full control over scroller width.  Hover state is driven
/// from the parent SwiftUI view via onHover so the scroller appears when the
/// mouse is anywhere over the sidebar, not just over the scroll area.
private struct SidebarScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    let isHovered: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.scrollerStyle = .overlay
        sv.drawsBackground = false
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = false

        // Narrow vertical scroller, hidden by default
        let vs = NSScroller()
        vs.controlSize = .mini
        vs.alphaValue = 0
        sv.verticalScroller = vs

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
        return sv
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let host = nsView.documentView as? NSHostingView<Content> {
            host.rootView = content
        }
        context.coordinator.setScrollerVisible(isHovered)
        context.coordinator.forceNarrow()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        weak var scrollView: NSScrollView?

        func setScrollerVisible(_ visible: Bool) {
            let targetAlpha: CGFloat = visible ? 1 : 0
            guard scrollView?.verticalScroller?.alphaValue != targetAlpha else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = visible ? 0.15 : 0.3
                scrollView?.verticalScroller?.animator().alphaValue = targetAlpha
            }
        }

        func forceNarrow() {
            guard let sv = scrollView else { return }
            if let vs = sv.verticalScroller, vs.frame.width > sidebarScrollerWidth + 0.5 {
                var f = vs.frame
                f.size.width = sidebarScrollerWidth
                vs.frame = f
            }
        }
    }
}
