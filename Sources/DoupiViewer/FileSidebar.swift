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
        case .html:     return "html"
        case .markdown: return "markdown"
        case .code:     return "html"
        case .image:    return "image"
        case .pdf:      return "pdf"
        case .text:     return "default"
        case .tsx:      return "react"
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

private extension URL {
    var setiIconName: String {
        switch pathExtension.lowercased() {
        case "html", "htm":  return "html"
        case "swift":        return "swift"
        case "pdf":          return "pdf"
        case "js", "mjs", "cjs": return "javascript"
        case "ts", "mts", "cts": return "typescript"
        case "tsx", "jsx":  return "react"
        case "css", "scss", "less": return "css"
        case "json":         return "json"
        case "md", "markdown": return "markdown"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tiff", "tif", "ico": return "image"
        case "yaml", "yml": return "yml"
        case "toml":         return "config"
        case "py":           return "python"
        case "sh", "bash", "zsh": return "shell"
        case "sql":          return "db"
        case "c", "h":      return "c"
        case "cpp", "hpp":  return "cpp"
        case "go":           return "go"
        case "rs":           return "rust"
        case "rb":           return "ruby"
        case "java", "kt", "scala": return "java"
        case "php":          return "php"
        case "lua":          return "lua"
        case "dart":         return "dart"
        case "svelte":       return "svelte"
        case "vue":          return "vue"
        case "xml":          return "xml"
        default:              return "default"
        }
    }
}

private enum SetiIconStore {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(named name: String) -> NSImage? {
        let key = name as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let url = Bundle.module.url(
            forResource: "seti-\(name)",
            withExtension: "svg",
            subdirectory: "Resources/SetiIcons"
        ), let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        cache.setObject(image, forKey: key)
        return image
    }
}

private struct SetiFileIcon: View {
    let name: String
    let color: Color

    var body: some View {
        Group {
            if let image = SetiIconStore.image(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(color)
            } else {
                Image(systemName: "doc")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(color)
            }
        }
        .frame(width: 18, height: 18)
        .frame(width: 18, alignment: .trailing)
        .offset(x: 2)
    }
}

private struct FileTypeIcon: View {
    let url: URL
    let color: Color

    var body: some View {
        SetiFileIcon(name: url.setiIconName, color: color)
    }
}

/// Gives every sidebar symbol the same visual canvas. SF Symbols have different
/// intrinsic aspect ratios, so a shared font size alone does not look uniform.
private struct SidebarIcon: View {
    let name: String
    let color: Color

    var body: some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .foregroundStyle(color)
            .frame(width: 13, height: 13)
            .frame(width: 18, alignment: .trailing)
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
    @State private var selectedTag: String? = nil
    @State private var tagVersion = UUID()
    @State private var showNewTagAlert = false
    @State private var newTagName = ""
    @State private var pendingTagURL: URL? = nil
    @State private var pinnedURLs: Set<URL> = []
    @State private var isFormatFilterExpanded = true
    @State private var isTagFilterExpanded = true
    @State private var isFormatHeaderHovered = false
    @State private var isTagHeaderHovered = false
    @State private var isLibraryHeaderHovered = false
    @State private var isRecentHeaderHovered = false
    @State private var isLibraryHovered = false
    @State private var isRecentHovered = false
    @State private var isLibraryExpanded = true
    @State private var isRecentExpanded = true
    @State private var libraryFolders: [LibraryFolder] = []
    @State private var showFolderNameAlert = false
    @State private var folderName = ""
    @State private var renamingFolderID: UUID? = nil
    @State private var newFolderParentID: UUID? = nil
    @State private var folderPendingDeletion: LibraryFolder? = nil

    /// External binding to focus filter from ContentView keyboard shortcut.
    var focusFilter: Binding<Bool>?

    private var hasActiveFilters: Bool {
        !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedFormat != nil
            || selectedTag != nil
    }

    private var filteredLibraryFolders: [LibraryFolder] {
        guard hasActiveFilters else { return libraryFolders }
        return libraryFolders.compactMap { filterFolder($0, queryMatchedByAncestor: false) }
    }

    private var allLibraryURLs: [URL] {
        libraryFolders.flatMap(allURLs)
    }

    private var filteredRootFiles: (folderID: UUID, files: [LibraryFile])? {
        guard let inbox = filteredLibraryFolders.first(where: isSystemInbox) else { return nil }
        return (inbox.id, inbox.files)
    }

    private var filteredTopLevelFolders: [LibraryFolder] {
        filteredLibraryFolders.filter { !isSystemInbox($0) }
    }

    private var filteredPinnedURLs: [URL] {
        pinnedURLs
            .filter { url in
                let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
                let matchesText = query.isEmpty || url.lastPathComponent.localizedCaseInsensitiveContains(query)
                let matchesFormat = selectedFormat == nil || FileFormat.for(url) == selectedFormat
                let matchesTag = selectedTag == nil || FileTags.tags(for: url).contains(selectedTag!)
                return matchesText && matchesFormat && matchesTag
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchAndFilterSection
                .id(tagVersion)
            if isLibraryExpanded {
                librarySection
                    .frame(maxHeight: .infinity)
                    .padding(.top, isTagFilterExpanded ? 4 : 0)
            } else {
                librarySection
                    .padding(.top, isTagFilterExpanded ? 4 : 0)
            }
            recentSection
                .padding(.top, isLibraryExpanded ? 4 : 0)
            if !isLibraryExpanded && !isRecentExpanded {
                Spacer(minLength: 0)
            }
        }
        .background(isDropTargeted ? Color.appAccent.opacity(0.08) : Color.appInfoBg)
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(isDropTargeted ? Color.appAccent : Color.clear, lineWidth: 0.5)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .frame(minWidth: 200)
        .onAppear {
            recentFiles = FileHistory.load()
            pinnedURLs = PinnedFiles.load()
            libraryFolders = LibraryFolders.load()
        }
        .onChange(of: refreshToken) { _, _ in
            recentFiles = FileHistory.load()
            pinnedURLs = PinnedFiles.load()
            libraryFolders = LibraryFolders.load()
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
        .alert(renamingFolderID == nil ? "新建文件夹" : "重命名文件夹", isPresented: $showFolderNameAlert) {
            TextField("文件夹名称", text: $folderName)
            Button("取消", role: .cancel) {
                renamingFolderID = nil
                newFolderParentID = nil
            }
            Button("保存") {
                let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                if let id = renamingFolderID {
                    LibraryFolders.rename(id, to: name, in: &libraryFolders)
                } else {
                    LibraryFolders.createFolder(named: name, parentID: newFolderParentID, in: &libraryFolders)
                }
                renamingFolderID = nil
                newFolderParentID = nil
            }
        } message: {
            Text("文件夹只存在于 Doupi，不会修改磁盘内容")
        }
        .confirmationDialog(
            "删除“\(folderPendingDeletion?.name ?? "")”？",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } }
            )
        ) {
            Button("删除 Doupi 文件夹", role: .destructive) {
                if let folder = folderPendingDeletion {
                    LibraryFolders.remove(folder.id, from: &libraryFolders)
                }
                folderPendingDeletion = nil
            }
            Button("取消", role: .cancel) { folderPendingDeletion = nil }
        } message: {
            Text("只删除 Doupi 中的组织结构，磁盘原文件不会被删除。")
        }
    }

    private var librarySection: some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Button { isLibraryExpanded.toggle() } label: {
                    HStack(spacing: 4) {
                        Text("文件")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.appMuted)
                        Image(systemName: isLibraryExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.appMuted)
                            .frame(width: 8)
                            .opacity(isLibraryHeaderHovered ? 1 : 0)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                Button {
                    renamingFolderID = nil
                    newFolderParentID = nil
                    folderName = ""
                    showFolderNameAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.appMuted)
                }
                .buttonStyle(.plain)
                .help("新建 Doupi 文件夹")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(.horizontal, 4)
            .onHover { isLibraryHeaderHovered = $0 }

            if isLibraryExpanded && libraryFolders.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 20, weight: .light))
                    Text("拖入文件夹，或新建一个")
                        .font(.system(size: 11))
                }
                .foregroundColor(.appMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                Spacer()
            } else if isLibraryExpanded && filteredTopLevelFolders.isEmpty && filteredRootFiles?.files.isEmpty != false {
                VStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .light))
                    Text("没有匹配的文件")
                        .font(.system(size: 11))
                    Button("清除筛选") { clearFilters() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.appAccent)
                }
                .foregroundColor(.appMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                Spacer()
            } else if isLibraryExpanded {
                SidebarScrollView(
                    content: VStack(spacing: 0) {
                        if !filteredPinnedURLs.isEmpty {
                            PinnedFilesBranch(
                                urls: filteredPinnedURLs,
                                selectedURL: selectedURL,
                                onSelect: { selectedURL = $0 },
                                onNewTag: beginCreatingTag,
                                onMetadataChanged: refreshMetadata,
                                onTogglePin: togglePin
                            )
                        }
                        LibraryFolderTree(
                            folders: filteredTopLevelFolders,
                            selectedURL: selectedURL,
                            onSelectFile: { selectedURL = $0 },
                            onRenameFolder: { folder in
                                renamingFolderID = folder.id
                                folderName = folder.name
                                showFolderNameAlert = true
                            },
                            onRemoveFolder: { folder in
                                folderPendingDeletion = folder
                            },
                            onImportIntoFolder: { folderID, providers in
                                handleDrop(providers, into: folderID)
                            },
                            onCreateChildFolder: { folder in
                                renamingFolderID = nil
                                newFolderParentID = folder.id
                                folderName = ""
                                showFolderNameAlert = true
                            },
                            onRemoveFile: { folderID, fileID in
                                LibraryFolders.removeFile(fileID, from: folderID, in: &libraryFolders)
                            },
                            pinnedURLs: pinnedURLs,
                            onNewTag: beginCreatingTag,
                            onMetadataChanged: refreshMetadata,
                            onTogglePin: togglePin
                        )
                        if let root = filteredRootFiles {
                            ForEach(root.files) { file in
                                LibraryFileRow(
                                    file: file,
                                    depth: 0,
                                    isSelected: selectedURL?.standardizedFileURL == file.sourceURL.standardizedFileURL,
                                    onSelect: { selectedURL = file.sourceURL },
                                    onRemove: {
                                        LibraryFolders.removeFile(file.id, from: root.folderID, in: &libraryFolders)
                                    },
                                    isPinned: pinnedURLs.contains(file.sourceURL.standardizedFileURL),
                                    onNewTag: beginCreatingTag,
                                    onMetadataChanged: refreshMetadata,
                                    onTogglePin: togglePin
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 4),
                    isHovered: isLibraryHovered
                )
                .onHover { isLibraryHovered = $0 }
            }
        }
        .background(Color.appInfoBg)
    }

    private var searchAndFilterSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.appMuted)
                TextField("筛选文件...", text: $filterText)
                    .font(.system(size: 12))
                    .foregroundColor(.appText)
                    .textFieldStyle(.plain)
                    .focused($isFilterFocused)
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

            VStack(alignment: .leading, spacing: 2) {
                Button(action: { isFormatFilterExpanded.toggle() }) {
                    HStack(spacing: 4) {
                        Text("格式筛选")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.appMuted)
                        Image(systemName: isFormatFilterExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.appMuted)
                            .frame(width: 8)
                            .opacity(isFormatHeaderHovered ? 1 : 0)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
                .onHover { isFormatHeaderHovered = $0 }

                if isFormatFilterExpanded {
                    FormatRow(
                        label: "全部",
                        icon: "default",
                        count: allLibraryURLs.count,
                        isSelected: selectedFormat == nil
                    ) { selectedFormat = nil }

                    ForEach(FileFormat.allCases, id: \.self) { format in
                        let count = allLibraryURLs.filter { FileFormat.for($0) == format }.count
                        if count > 0 {
                            FormatRow(
                                label: format.rawValue,
                                icon: format.icon,
                                count: count,
                                isSelected: selectedFormat == format
                            ) { selectedFormat = selectedFormat == format ? nil : format }
                        }
                    }
                }
            }
            .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 2) {
                Button(action: { isTagFilterExpanded.toggle() }) {
                    HStack(spacing: 4) {
                        Text("标签筛选")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.appMuted)
                        Image(systemName: isTagFilterExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.appMuted)
                            .frame(width: 8)
                            .opacity(isTagHeaderHovered ? 1 : 0)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
                .onHover { isTagHeaderHovered = $0 }

                if isTagFilterExpanded {
                    TagRow(
                        label: "全部",
                        count: allLibraryURLs.count,
                        isSelected: selectedTag == nil,
                        action: { selectedTag = nil }
                    )

                    ForEach(FileTags.allTags(), id: \.self) { tag in
                        let count = allLibraryURLs.filter { FileTags.tags(for: $0).contains(tag) }.count
                        if count > 0 {
                            TagRow(
                                label: tag,
                                count: count,
                                isSelected: selectedTag == tag,
                                action: { selectedTag = selectedTag == tag ? nil : tag }
                            )
                        }
                    }
                }
            }
            .padding(.top, isFormatFilterExpanded ? 4 : 0)
            .padding(.bottom, 4)
        }
    }

    private var recentSection: some View {
        VStack(spacing: 3) {
            Button { isRecentExpanded.toggle() } label: {
                HStack(spacing: 4) {
                    Text("最近打开")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.appMuted)
                    Image(systemName: isRecentExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.appMuted)
                        .frame(width: 8)
                        .opacity(isRecentHeaderHovered ? 1 : 0)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .onHover { isRecentHeaderHovered = $0 }

            if isRecentExpanded {
                if recentFiles.isEmpty {
                    Text("还没有打开过文件")
                        .font(.system(size: 11))
                        .foregroundColor(.appMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 9)
                } else {
                    SidebarScrollView(
                        content: VStack(spacing: 0) {
                            ForEach(recentFiles, id: \.self) { url in
                                SidebarRow(
                                    url: url,
                                    isSelected: selectedURL == url,
                                    isKeyboardFocused: false,
                                    onClearKeyboardFocus: { },
                                    action: { selectedURL = url }
                                )
                                .contextMenu { recentContextMenu(for: url) }
                            }
                        },
                        isHovered: isRecentHovered
                    )
                    .frame(height: isLibraryExpanded ? min(CGFloat(recentFiles.count) * 31, 310) : nil)
                    .frame(maxHeight: isLibraryExpanded ? nil : .infinity)
                    .onHover { isRecentHovered = $0 }
                }
            }
        }
        .background(Color.appInfoBg)
    }

    // MARK: - Helpers

    private func allURLs(_ folder: LibraryFolder) -> [URL] {
        folder.files.map(\.sourceURL) + folder.folders.flatMap(allURLs)
    }

    private func isSystemInbox(_ folder: LibraryFolder) -> Bool {
        folder.name == "未分类" && folder.folders.isEmpty
    }

    private func filterFolder(_ folder: LibraryFolder, queryMatchedByAncestor: Bool) -> LibraryFolder? {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderMatchesQuery = !query.isEmpty && folder.name.localizedCaseInsensitiveContains(query)
        let queryAlreadyMatched = queryMatchedByAncestor || folderMatchesQuery

        let files = folder.files.filter { file in
            let matchesText = query.isEmpty || queryAlreadyMatched || file.name.localizedCaseInsensitiveContains(query)
            let matchesFormat = selectedFormat == nil || FileFormat.for(file.sourceURL) == selectedFormat
            let matchesTag = selectedTag == nil || FileTags.tags(for: file.sourceURL).contains(selectedTag!)
            return matchesText && matchesFormat && matchesTag
        }
        let children = folder.folders.compactMap {
            filterFolder($0, queryMatchedByAncestor: queryAlreadyMatched)
        }

        let hasAttributeFilter = selectedFormat != nil || selectedTag != nil
        guard (!hasAttributeFilter && folderMatchesQuery) || !files.isEmpty || !children.isEmpty else { return nil }
        return LibraryFolder(id: folder.id, name: folder.name, folders: children, files: files)
    }

    private func clearFilters() {
        filterText = ""
        selectedFormat = nil
        selectedTag = nil
    }

    private func beginCreatingTag(for url: URL) {
        pendingTagURL = url
        newTagName = ""
        showNewTagAlert = true
    }

    private func refreshMetadata() {
        tagVersion = UUID()
    }

    @ViewBuilder
    private func recentContextMenu(for url: URL) -> some View {
        FileItemContextMenu(
            url: url,
            isPinned: pinnedURLs.contains(url.standardizedFileURL),
            onNewTag: beginCreatingTag,
            onMetadataChanged: refreshMetadata,
            onTogglePin: togglePin,
            removeTitle: "从最近打开移除",
            onRemove: { removeFromRecent(url) }
        )
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task {
            let droppedURLs = await FileDropDelegate.collectURLs(from: providers)
            guard !droppedURLs.isEmpty else { return }
            let imported = await Task.detached { LibraryFolders.prepareImport(droppedURLs) }.value
            await MainActor.run {
                LibraryFolders.apply(imported, into: &libraryFolders)
            }
        }
        return true
    }

    private func handleDrop(_ providers: [NSItemProvider], into folderID: UUID) -> Bool {
        Task {
            let droppedURLs = await FileDropDelegate.collectURLs(from: providers)
            guard !droppedURLs.isEmpty else { return }
            let imported = await Task.detached { LibraryFolders.prepareImport(droppedURLs) }.value
            await MainActor.run {
                LibraryFolders.apply(imported, into: folderID, in: &libraryFolders)
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

// MARK: - Library Folder Tree

private struct LibraryFolderTree: View {
    let folders: [LibraryFolder]
    let selectedURL: URL?
    let onSelectFile: (URL) -> Void
    let onRenameFolder: (LibraryFolder) -> Void
    let onRemoveFolder: (LibraryFolder) -> Void
    let onImportIntoFolder: (UUID, [NSItemProvider]) -> Bool
    let onCreateChildFolder: (LibraryFolder) -> Void
    let onRemoveFile: (UUID, UUID) -> Void
    let pinnedURLs: Set<URL>
    let onNewTag: (URL) -> Void
    let onMetadataChanged: () -> Void
    let onTogglePin: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(folders) { folder in
                LibraryFolderBranch(
                    folder: folder,
                    depth: 0,
                    selectedURL: selectedURL,
                    onSelectFile: onSelectFile,
                    onRenameFolder: onRenameFolder,
                    onRemoveFolder: onRemoveFolder,
                    onImportIntoFolder: onImportIntoFolder,
                    onCreateChildFolder: onCreateChildFolder,
                    onRemoveFile: onRemoveFile,
                    pinnedURLs: pinnedURLs,
                    onNewTag: onNewTag,
                    onMetadataChanged: onMetadataChanged,
                    onTogglePin: onTogglePin
                )
            }
        }
    }
}

private struct LibraryFolderBranch: View {
    let folder: LibraryFolder
    let depth: Int
    let selectedURL: URL?
    let onSelectFile: (URL) -> Void
    let onRenameFolder: (LibraryFolder) -> Void
    let onRemoveFolder: (LibraryFolder) -> Void
    let onImportIntoFolder: (UUID, [NSItemProvider]) -> Bool
    let onCreateChildFolder: (LibraryFolder) -> Void
    let onRemoveFile: (UUID, UUID) -> Void
    let pinnedURLs: Set<URL>
    let onNewTag: (URL) -> Void
    let onMetadataChanged: () -> Void
    let onTogglePin: (URL) -> Void
    @State private var isExpanded = true
    @State private var isHovering = false

    private var hasExpandableContent: Bool {
        !folder.folders.isEmpty || !folder.files.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                if hasExpandableContent { isExpanded.toggle() }
            } label: {
                HStack(spacing: depth > 0 ? 3 : 6) {
                    SidebarIcon(
                        name: isExpanded ? "folder.fill" : "folder",
                        color: .appMuted
                    )
                        .offset(x: depth > 0 ? -3 : 0)
                    Text(folder.name)
                        .font(.system(size: 13))
                        .foregroundColor(.appText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7)
                .padding(.leading, 10 + CGFloat(depth) * 22)
                .padding(.trailing, 10)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovering ? Color.appHoverBg : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }

            if isExpanded {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(folder.folders) { child in
                    LibraryFolderBranch(
                        folder: child,
                        depth: depth + 1,
                        selectedURL: selectedURL,
                        onSelectFile: onSelectFile,
                        onRenameFolder: onRenameFolder,
                        onRemoveFolder: onRemoveFolder,
                        onImportIntoFolder: onImportIntoFolder,
                        onCreateChildFolder: onCreateChildFolder,
                        onRemoveFile: onRemoveFile,
                        pinnedURLs: pinnedURLs,
                        onNewTag: onNewTag,
                        onMetadataChanged: onMetadataChanged,
                        onTogglePin: onTogglePin
                    )
                }
                ForEach(folder.files) { file in
                    LibraryFileRow(
                        file: file,
                        depth: depth + 1,
                        isSelected: selectedURL?.standardizedFileURL == file.sourceURL.standardizedFileURL,
                        onSelect: { onSelectFile(file.sourceURL) },
                        onRemove: { onRemoveFile(folder.id, file.id) },
                        isPinned: pinnedURLs.contains(file.sourceURL.standardizedFileURL),
                        onNewTag: onNewTag,
                        onMetadataChanged: onMetadataChanged,
                        onTogglePin: onTogglePin
                    )
                }
            }
            }
        }
        .contextMenu {
            Button("新建子文件夹") { onCreateChildFolder(folder) }
            Button("重命名") { onRenameFolder(folder) }
            Divider()
            Button("删除文件夹", role: .destructive) { onRemoveFolder(folder) }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers, _ in
            onImportIntoFolder(folder.id, providers)
        }
    }
}

private struct LibraryFileRow: View {
    let file: LibraryFile
    let depth: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: (() -> Void)?
    let isPinned: Bool
    let onNewTag: (URL) -> Void
    let onMetadataChanged: () -> Void
    let onTogglePin: (URL) -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: depth > 0 ? 3 : 6) {
            Group {
                if file.isAvailable {
                    FileTypeIcon(
                        url: file.sourceURL,
                        color: isSelected ? .appAccent : .appMuted
                    )
                } else {
                    SidebarIcon(name: "exclamationmark.triangle", color: .orange)
                }
            }
                .offset(x: depth > 0 ? -3 : 0)
            Text(file.name)
                .font(.system(size: 13))
                .foregroundColor(file.isAvailable ? .appText : .appMuted)
                .lineLimit(1)
            Spacer(minLength: 0)

            Button { onTogglePin(file.sourceURL) } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isPinned ? .appAccent : .appMuted)
            }
            .buttonStyle(.plain)
            .opacity(isPinned || isHovering ? 1 : 0)
            .scaleEffect(isPinned || isHovering ? 1 : 0.85, anchor: .trailing)
        }
        .padding(.vertical, 7)
        .padding(.leading, 10 + CGFloat(depth) * 22)
        .padding(.trailing, 10)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.appSelectedBg : (isHovering ? Color.appHoverBg : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if file.isAvailable { onSelect() }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .help(file.isAvailable ? file.sourceURL.path : "原文件已移动或删除")
        .contextMenu {
            FileItemContextMenu(
                url: file.sourceURL,
                isPinned: isPinned,
                onNewTag: onNewTag,
                onMetadataChanged: onMetadataChanged,
                onTogglePin: onTogglePin,
                removeTitle: onRemove == nil ? nil : "从文件夹移除",
                onRemove: onRemove
            )
        }
    }
}

private struct PinnedFilesBranch: View {
    let urls: [URL]
    let selectedURL: URL?
    let onSelect: (URL) -> Void
    let onNewTag: (URL) -> Void
    let onMetadataChanged: () -> Void
    let onTogglePin: (URL) -> Void
    @State private var isExpanded = true
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: 6) {
                    SidebarIcon(name: "pin.fill", color: .appMuted)
                    Text("置顶")
                        .font(.system(size: 13))
                        .foregroundColor(.appText)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovering ? Color.appHoverBg : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }

            if isExpanded {
                ForEach(urls, id: \.self) { url in
                    LibraryFileRow(
                        file: LibraryFile(sourceURL: url),
                        depth: 1,
                        isSelected: selectedURL?.standardizedFileURL == url.standardizedFileURL,
                        onSelect: { onSelect(url) },
                        onRemove: nil,
                        isPinned: true,
                        onNewTag: onNewTag,
                        onMetadataChanged: onMetadataChanged,
                        onTogglePin: onTogglePin
                    )
                }
            }
        }
    }
}

private struct FileItemContextMenu: View {
    let url: URL
    let isPinned: Bool
    let onNewTag: (URL) -> Void
    let onMetadataChanged: () -> Void
    let onTogglePin: (URL) -> Void
    let removeTitle: String?
    let onRemove: (() -> Void)?

    var body: some View {
        if !FileTags.allTags().isEmpty {
            Menu("打标") {
                ForEach(FileTags.allTags(), id: \.self) { tag in
                    let tagged = FileTags.tags(for: url).contains(tag)
                    Button {
                        FileTags.toggleTag(tag, for: url)
                        onMetadataChanged()
                    } label: {
                        if tagged { Label(tag, systemImage: "checkmark") } else { Text(tag) }
                    }
                }
            }
            Divider()
        }
        Button("新建标签...") { onNewTag(url) }
        Divider()
        Button(isPinned ? "取消置顶" : "置顶") { onTogglePin(url) }
        if let removeTitle, let onRemove {
            Divider()
            Button(removeTitle) { onRemove() }
        }
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let url: URL
    let isSelected: Bool
    let isKeyboardFocused: Bool
    let onClearKeyboardFocus: () -> Void
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            FileTypeIcon(
                url: url,
                color: isSelected ? .appAccent : .appMuted
            )

            Text(url.lastPathComponent)
                .font(.system(size: 13))
                .foregroundColor(.appText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
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
        HStack(spacing: 6) {
            SetiFileIcon(
                name: icon,
                color: isSelected ? .appAccent : .appMuted
            )

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
        HStack(spacing: 6) {
            SidebarIcon(
                name: "tag",
                color: isSelected ? .appAccent : .appMuted
            )

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
