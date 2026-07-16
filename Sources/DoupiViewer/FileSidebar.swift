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
    @State private var selectedTag: String? = nil
    @State private var tagVersion = UUID()
    @State private var showNewTagAlert = false
    @State private var newTagName = ""
    @State private var pendingTagURL: URL? = nil
    @State private var pinnedURLs: Set<URL> = []
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

    var body: some View {
        VStack(spacing: 0) {
            searchAndFilterBar
                .id(tagVersion)
            librarySection
                .frame(maxHeight: .infinity)
            recentSection
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
        VStack(spacing: 6) {
            HStack {
                Text("文件夹")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.appText)
                Spacer()
                Button {
                    renamingFolderID = nil
                    newFolderParentID = nil
                    folderName = ""
                    showFolderNameAlert = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.appMuted)
                }
                .buttonStyle(.plain)
                .help("新建 Doupi 文件夹")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            if libraryFolders.isEmpty {
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
            } else if filteredLibraryFolders.isEmpty {
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
            } else {
                ScrollView {
                    LibraryFolderTree(
                        folders: filteredLibraryFolders,
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
                        }
                    )
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding(.bottom, 8)
        .background(Color.appInfoBg)
    }

    private var searchAndFilterBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.appMuted)
                    TextField("搜索所有文件...", text: $filterText)
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                        .focused($isFilterFocused)
                    if !filterText.isEmpty {
                        Button { filterText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.appMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Menu {
                    Menu("格式") {
                        Button("全部格式") { selectedFormat = nil }
                        ForEach(FileFormat.allCases, id: \.self) { format in
                            Button {
                                selectedFormat = selectedFormat == format ? nil : format
                            } label: {
                                if selectedFormat == format {
                                    Label(format.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(format.rawValue)
                                }
                            }
                        }
                    }
                    if !FileTags.allTags().isEmpty {
                        Menu("标签") {
                            Button("全部标签") { selectedTag = nil }
                            ForEach(FileTags.allTags(), id: \.self) { tag in
                                Button {
                                    selectedTag = selectedTag == tag ? nil : tag
                                } label: {
                                    if selectedTag == tag {
                                        Label(tag, systemImage: "checkmark")
                                    } else {
                                        Text(tag)
                                    }
                                }
                            }
                        }
                    }
                    if selectedFormat != nil || selectedTag != nil {
                        Divider()
                        Button("清除筛选") { clearFilters() }
                    }
                } label: {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 15))
                        .foregroundColor(hasActiveFilters ? .appAccent : .appMuted)
                        .frame(width: 28, height: 28)
                        .background(hasActiveFilters ? Color.appAccentDimmed : Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("筛选文件")
            }

            if selectedFormat != nil || selectedTag != nil {
                HStack(spacing: 5) {
                    if let format = selectedFormat {
                        FilterChip(label: format.rawValue) { selectedFormat = nil }
                    }
                    if let tag = selectedTag {
                        FilterChip(label: tag) { selectedTag = nil }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.appSurface.opacity(0.72))
    }

    private var recentSection: some View {
        VStack(spacing: 3) {
            Button { isRecentExpanded.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: isRecentExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.appMuted)
                    Text("最近打开")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.appText)
                    Spacer()
                    Text("\(recentFiles.count)")
                        .font(.system(size: 10))
                        .foregroundColor(.appMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)

            if isRecentExpanded {
                if recentFiles.isEmpty {
                    Text("还没有打开过文件")
                        .font(.system(size: 11))
                        .foregroundColor(.appMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 9)
                } else {
                    ForEach(Array(recentFiles.prefix(5)), id: \.self) { url in
                        SidebarRow(
                            url: url,
                            isSelected: selectedURL == url,
                            isKeyboardFocused: false,
                            isPinned: pinnedURLs.contains(url.standardizedFileURL),
                            onTogglePin: { togglePin(url) },
                            onClearKeyboardFocus: { },
                            action: { selectedURL = url }
                        )
                        .contextMenu { recentContextMenu(for: url) }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .background(Color.appSurface.opacity(0.62))
    }

    // MARK: - Helpers

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

    @ViewBuilder
    private func recentContextMenu(for url: URL) -> some View {
        if !FileTags.allTags().isEmpty {
            Menu("打标") {
                ForEach(FileTags.allTags(), id: \.self) { tag in
                    let tagged = FileTags.tags(for: url).contains(tag)
                    Button {
                        FileTags.toggleTag(tag, for: url)
                        tagVersion = UUID()
                    } label: {
                        if tagged { Label(tag, systemImage: "checkmark") } else { Text(tag) }
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
        Button("从最近打开移除") { removeFromRecent(url) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task {
            let droppedURLs = await FileDropDelegate.collectURLs(from: providers)
            guard !droppedURLs.isEmpty else { return }
            let imported = await Task.detached { LibraryFolders.prepareImport(droppedURLs) }.value
            let renderableURLs = imported.allFileURLs.filter { FileInfo.from(url: $0)?.isRenderable == true }
            await MainActor.run {
                LibraryFolders.apply(imported, into: &libraryFolders)
                FileHistory.bulkAdd(renderableURLs)
                recentFiles = FileHistory.load()
                if let first = renderableURLs.first { selectedURL = first }
            }
        }
        return true
    }

    private func handleDrop(_ providers: [NSItemProvider], into folderID: UUID) -> Bool {
        Task {
            let droppedURLs = await FileDropDelegate.collectURLs(from: providers)
            guard !droppedURLs.isEmpty else { return }
            let imported = await Task.detached { LibraryFolders.prepareImport(droppedURLs) }.value
            let renderableURLs = imported.allFileURLs.filter { FileInfo.from(url: $0)?.isRenderable == true }
            await MainActor.run {
                LibraryFolders.apply(imported, into: folderID, in: &libraryFolders)
                FileHistory.bulkAdd(renderableURLs)
                recentFiles = FileHistory.load()
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

private struct FilterChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 4) {
                Text(label)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.appAccentDeep)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.appAccentDimmed)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(folders) { folder in
                LibraryFolderBranch(
                    folder: folder,
                    selectedURL: selectedURL,
                    onSelectFile: onSelectFile,
                    onRenameFolder: onRenameFolder,
                    onRemoveFolder: onRemoveFolder,
                    onImportIntoFolder: onImportIntoFolder,
                    onCreateChildFolder: onCreateChildFolder,
                    onRemoveFile: onRemoveFile
                )
            }
        }
    }
}

private struct LibraryFolderBranch: View {
    let folder: LibraryFolder
    let selectedURL: URL?
    let onSelectFile: (URL) -> Void
    let onRenameFolder: (LibraryFolder) -> Void
    let onRemoveFolder: (LibraryFolder) -> Void
    let onImportIntoFolder: (UUID, [NSItemProvider]) -> Bool
    let onCreateChildFolder: (LibraryFolder) -> Void
    let onRemoveFile: (UUID, UUID) -> Void
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(folder.folders) { child in
                    LibraryFolderBranch(
                        folder: child,
                        selectedURL: selectedURL,
                        onSelectFile: onSelectFile,
                        onRenameFolder: onRenameFolder,
                        onRemoveFolder: onRemoveFolder,
                        onImportIntoFolder: onImportIntoFolder,
                        onCreateChildFolder: onCreateChildFolder,
                        onRemoveFile: onRemoveFile
                    )
                }
                ForEach(folder.files) { file in
                    Button {
                        if file.isAvailable { onSelectFile(file.sourceURL) }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: file.isAvailable ? "doc" : "exclamationmark.triangle")
                                .font(.system(size: 11))
                                .foregroundColor(file.isAvailable ? .appMuted : .orange)
                                .frame(width: 16)
                            Text(file.name)
                                .font(.system(size: 12))
                                .foregroundColor(file.isAvailable ? .appText : .appMuted)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selectedURL?.standardizedFileURL == file.sourceURL.standardizedFileURL ? Color.appSelectedBg : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(file.isAvailable ? file.sourceURL.path : "原文件已移动或删除")
                    .contextMenu {
                        Button("从文件夹移除") { onRemoveFile(folder.id, file.id) }
                    }
                }
            }
            .padding(.leading, 12)
        } label: {
            Label(folder.name, systemImage: isExpanded ? "folder.fill" : "folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.appText)
                .lineLimit(1)
                .padding(.vertical, 5)
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
