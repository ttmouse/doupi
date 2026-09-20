import SwiftUI
import UniformTypeIdentifiers

private let libraryFileDragType = UTType.plainText
private let libraryFileDragPrefix = "doupi-library-file:"
private let libraryFolderDragPrefix = "doupi-library-folder:"

private struct LibraryFileDragPayload: Codable {
    let fileID: UUID
    let sourceFolderID: UUID

    func itemProvider() -> NSItemProvider {
        let data = try? JSONEncoder().encode(self)
        let encoded = data?.base64EncodedString() ?? ""
        return NSItemProvider(object: (libraryFileDragPrefix + encoded) as NSString)
    }

    static func from(_ string: String) -> LibraryFileDragPayload? {
        guard string.hasPrefix(libraryFileDragPrefix),
              let data = Data(base64Encoded: String(string.dropFirst(libraryFileDragPrefix.count)))
        else { return nil }
        return try? JSONDecoder().decode(LibraryFileDragPayload.self, from: data)
    }
}

private struct LibraryFolderDragPayload: Codable {
    let folderID: UUID
    let sourceParentID: UUID?

    func itemProvider() -> NSItemProvider {
        let data = try? JSONEncoder().encode(self)
        let encoded = data?.base64EncodedString() ?? ""
        return NSItemProvider(object: (libraryFolderDragPrefix + encoded) as NSString)
    }

    static func from(_ string: String) -> LibraryFolderDragPayload? {
        guard string.hasPrefix(libraryFolderDragPrefix),
              let data = Data(base64Encoded: String(string.dropFirst(libraryFolderDragPrefix.count)))
        else { return nil }
        return try? JSONDecoder().decode(LibraryFolderDragPayload.self, from: data)
    }
}

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

/// 侧边栏的一行文件。同一个版本族只出现一行，行上挂的是当前版本的 `LibraryFile`。
private struct VersionedRow: Identifiable {
    let file: LibraryFile
    /// 非 nil 表示这一行代表一个版本族，行内可以切换版本。
    let family: VersionFamily?

    var id: UUID { file.id }
}

/// 搜索结果的版本行：多带上所在文件夹，用于扁平列表定位。
private struct VersionedSearchRow: Identifiable {
    let file: LibraryFile
    let family: VersionFamily?
    let sourceFolderID: UUID?
    let folderPath: String?

    var id: UUID { file.id }
}

/// 把一组**同磁盘目录**的文件收成侧边栏行：同一个版本族只留当前版本这一行，
/// 其余版本在该行的版本菜单里切换。目录不同就不归并——同名不等于同一份产物。
@MainActor
private func versionedRows(_ files: [LibraryFile]) -> [VersionedRow] {
    VersionFamilies.families(in: files).map { family in
        let current = VersionFamilies.current(
            of: family,
            chosen: VersionSelectionStore.shared.chosen(for: family.id)
        )
        return VersionedRow(file: current, family: family.isFamily ? family : nil)
    }
}

/// Sidebar with recent files history.
@MainActor
struct FileSidebar: View {

    @Binding var selectedURL: URL?
    var refreshToken: Int = 0
    @State private var recentFiles: [URL] = []
    @StateObject private var mounts = LibraryMountIndex()
    /// 版本选择是跨行共享的状态：某一族切了版本，所有展示它的位置都要跟着重算。
    @ObservedObject private var versionSelection = VersionSelectionStore.shared
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
    @State private var isFormatFilterPresented = false
    @State private var isTagFilterPresented = false
    @State private var isLibraryHeaderHovered = false
    @State private var isLibraryRootDropTarget = false
    @State private var isPinnedHeaderHovered = false
    @State private var isRecentHeaderHovered = false
    @State private var isLibraryHovered = false
    @State private var isRecentHovered = false
    @State private var isLibraryExpanded = true
    @State private var isPinnedExpanded = true
    @State private var isRecentExpanded = true
    @State private var collapsedFolderIDs: Set<UUID> = []
    @State private var libraryFolders: [LibraryFolder] = []
    @State private var showFolderNameAlert = false
    @State private var folderName = ""
    @State private var renamingFolderID: UUID? = nil
    @State private var newFolderParentID: UUID? = nil
    @State private var folderPendingDeletion: LibraryFolder? = nil
    @State private var filePendingDeletion: URL? = nil
    @State private var renamingFileURL: URL? = nil
    @State private var renamingFileRowID: String? = nil
    @State private var fileRenameName = ""
    @State private var keyboardFocusedURL: URL?

    /// External binding to focus filter from ContentView keyboard shortcut.
    var focusFilter: Binding<Bool>?

    private var searchQuery: SearchQuery { SearchQuery(filterText) }

    private var hasActiveFilters: Bool {
        !searchQuery.isEmpty
            || selectedFormat != nil
            || selectedTag != nil
    }

    /// 置顶区仅在无搜索/筛选时显示；搜索结果场景中让位给结果列表。
    private var isPinnedSectionVisible: Bool {
        !hasActiveFilters && !pinnedURLs.isEmpty
    }

    private var filteredLibraryFolders: [LibraryFolder] {
        guard hasActiveFilters else { return libraryFolders }
        return libraryFolders.compactMap { filterFolder($0, satisfiedByAncestors: []) }
    }

    /// 筛选计数要覆盖列表里实际展示的全部文件：虚拟文件树 + live 归档文件夹。
    private var allDisplayedURLs: [URL] {
        libraryFolders.flatMap(allURLs) + liveFolders.flatMap(allURLs)
    }

    private var filteredRootFiles: (folderID: UUID, files: [LibraryFile])? {
        guard let inbox = filteredLibraryFolders.first(where: isSystemInbox) else { return nil }
        return (inbox.id, inbox.files)
    }

    private var filteredTopLevelFolders: [LibraryFolder] {
        filteredLibraryFolders.filter { !isSystemInbox($0) }
    }

    /// 归档目录以 live 文件夹的形式挂在文件树底部：每次扫描重建，不写入用户的虚拟文件树。
    /// 搜索/筛选走扁平结果表，因此这里不需要过滤，只保留筛选计数要用的原始树。
    private var liveFolders: [LibraryFolder] { mounts.folders }

    private var visibleTopLevelFolders: [LibraryFolder] {
        filteredTopLevelFolders + liveFolders
    }

    /// live 文件夹只读：不参与拖拽重排、不写入虚拟文件树。
    private var liveFolderIDs: Set<UUID> {
        Set(liveFolders.flatMap(folderIDs(in:)))
    }

    private var filteredPinnedURLs: [URL] {
        pinnedURLs
            .filter { url in
                // 置顶列表不展示所在位置，所以只用文件名比——否则关键调会命中
                // 屏幕上根本看不到的磁盘路径，用户无从理解为什么这一行匹配了。
                let matchesText = searchQuery.matches(fileName: url.lastPathComponent, satisfiedByPath: [])
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
            if isPinnedSectionVisible {
                pinnedSection
                    .padding(.top, 4)
            }
            if isLibraryExpanded {
                librarySection
                    .frame(maxHeight: .infinity)
                    .padding(.top, isPinnedSectionVisible ? (isPinnedExpanded ? 4 : 0) : 4)
            } else {
                librarySection
                    .padding(.top, isPinnedSectionVisible ? (isPinnedExpanded ? 4 : 0) : 4)
            }
            recentSection
                .padding(.top, isLibraryExpanded ? 4 : 0)
            if !isLibraryExpanded && !isRecentExpanded {
                Spacer(minLength: 0)
            }
        }
        .background(isDropTargeted ? Color.appAccent.opacity(0.08) : Color.appInfoBg)
        .overlay {
            SidebarKeyboardHandler(
                urls: keyboardNavigationURLs,
                focusedURL: $keyboardFocusedURL,
                onOpen: { selectedURL = $0 },
                onClear: clearFilters
            )
        }
        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(isDropTargeted ? Color.appAccent : Color.clear, lineWidth: 0.5)
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .frame(minWidth: 200)
        .task { await mounts.monitor() }
        .onAppear {
            recentFiles = FileHistory.load()
            pinnedURLs = PinnedFiles.load()
            libraryFolders = LibraryFolders.load()
            loadExpansionState()
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
        .onChange(of: expansionState) { _, state in SidebarExpansionStore.save(state) }
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
                    collapsedFolderIDs.subtract(folderIDs(in: folder))
                }
                folderPendingDeletion = nil
            }
            Button("取消", role: .cancel) { folderPendingDeletion = nil }
        } message: {
            Text("只删除 Doupi 中的组织结构，磁盘原文件不会被删除。")
        }
        .confirmationDialog(
            "删除“\(filePendingDeletion?.lastPathComponent ?? "")”？",
            isPresented: Binding(
                get: { filePendingDeletion != nil },
                set: { if !$0 { filePendingDeletion = nil } }
            )
        ) {
            Button("移到废纸篓", role: .destructive) {
                if let url = filePendingDeletion { deleteSourceFile(url) }
                filePendingDeletion = nil
            }
            Button("取消", role: .cancel) { filePendingDeletion = nil }
        } message: {
            Text("这会删除磁盘中的源文件，并从 Doupi 的文件列表、置顶和最近打开中移除。")
        }
    }

    private var pinnedSection: some View {
        VStack(spacing: 3) {
            Button { isPinnedExpanded.toggle() } label: {
                HStack(spacing: 4) {
                    Text("置顶")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.appMuted)
                    Image(systemName: isPinnedExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.appMuted)
                        .frame(width: 8)
                        .opacity(isPinnedHeaderHovered ? 1 : 0)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .onHover { isPinnedHeaderHovered = $0 }

            if isPinnedExpanded {
                VStack(spacing: 0) {
                    ForEach(filteredPinnedURLs, id: \.self) { url in
                        LibraryFileRow(
                            file: LibraryFile(sourceURL: url),
                            depth: 0,
                            sourceFolderID: nil,
                            renameRowID: "pinned:\(url.standardizedFileURL.path)",
                            isSelected: selectedURL?.standardizedFileURL == url.standardizedFileURL,
                            onSelect: { selectedURL = $0 },
                            onRemove: nil,
                            isPinned: true,
                            onNewTag: beginCreatingTag,
                            onMetadataChanged: refreshMetadata,
                            onTogglePin: togglePin,
                            onRenameFile: beginRenamingFile,
                            renamingFileURL: renamingFileURL,
                            renamingFileRowID: renamingFileRowID,
                            fileRenameName: $fileRenameName,
                            onRenameCommit: commitRenamingFile,
                            onRenameCancel: cancelRenamingFile,
                            onRequestDelete: requestSourceDeletion
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .background(Color.appInfoBg)
    }

    private var librarySection: some View {
        VStack(spacing: 3) {
            // 搜索结果场景不显示“文件”标题，直接展示结果列表
            if !hasActiveFilters {
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
                Menu {
                    Button("添加文件") { addSingleFile() }
                    Button("添加文件夹") { addExistingFolder() }
                    Divider()
                    Button("新建文件夹") { beginCreatingFolder() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.appMuted)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .tint(.appMuted)
                .help("添加或新建")
                .opacity(isLibraryHeaderHovered ? 1 : 0)
                .allowsHitTesting(isLibraryHeaderHovered)
                .offset(x: 3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isLibraryRootDropTarget ? Color.appAccent.opacity(0.16) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(.horizontal, 4)
            .onHover { isLibraryHeaderHovered = $0 }
            .onDrop(of: [libraryFileDragType, .fileURL], isTargeted: $isLibraryRootDropTarget) { providers, _ in
                handleDropIntoRoot(providers)
            }
            }

            if hasActiveFilters {
                searchResultsSection
            } else if isLibraryExpanded && visibleTopLevelFolders.isEmpty && filteredRootFiles == nil {
                VStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 20, weight: .light))
                    Text("拖入文件或文件夹，或新建文件夹")
                        .font(.system(size: 11))
                }
                .foregroundColor(.appMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                Spacer()
            } else if isLibraryExpanded {
                SidebarScrollView(
                    content: VStack(spacing: 0) {
                        LibraryFolderTree(
                            folders: visibleTopLevelFolders,
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
                            onTogglePin: togglePin,
                            onRenameFile: beginRenamingFile,
                            collapsedFolderIDs: $collapsedFolderIDs,
                            renamingFileURL: renamingFileURL,
                            renamingFileRowID: renamingFileRowID,
                            fileRenameName: $fileRenameName,
                            onRenameCommit: commitRenamingFile,
                            onRenameCancel: cancelRenamingFile,
                            onRequestDelete: requestSourceDeletion,
                            liveFolderIDs: liveFolderIDs
                        )
                        if let root = filteredRootFiles {
                            ForEach(versionedRows(root.files)) { row in
                                LibraryFileRow(
                                    file: row.file,
                                    depth: 0,
                                    sourceFolderID: root.folderID,
                                    renameRowID: "library:\(row.file.id.uuidString)",
                                    isSelected: selectedURL?.standardizedFileURL == row.file.sourceURL.standardizedFileURL,
                                    onSelect: { selectedURL = $0 },
                                    onRemove: {
                                        LibraryFolders.removeFile(row.file.id, from: root.folderID, in: &libraryFolders)
                                    },
                                    isPinned: pinnedURLs.contains(row.file.sourceURL.standardizedFileURL),
                                    onNewTag: beginCreatingTag,
                                    onMetadataChanged: refreshMetadata,
                                    onTogglePin: togglePin,
                                    onRenameFile: beginRenamingFile,
                                    renamingFileURL: renamingFileURL,
                                    renamingFileRowID: renamingFileRowID,
                                    fileRenameName: $fileRenameName,
                                    onRenameCommit: commitRenamingFile,
                                    onRenameCancel: cancelRenamingFile,
                                    onRequestDelete: requestSourceDeletion,
                                    versionFamily: row.family
                                )
                            }
                        }
                        if let error = mounts.errorMessage {
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                                .textSelection(.enabled)
                                .padding(.horizontal, 14)
                                .padding(.top, 4)
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

    /// 当前筛选结果的键盘导航顺序。箭头只移动光标，Enter 才打开文件，避免误打开。
    private var keyboardNavigationURLs: [URL] {
        versionedSearchRows(collectSearchResults()).map { $0.file.sourceURL.standardizedFileURL }
    }

    /// 搜索/筛选激活时的独立搜索结果场景：扁平列出所有匹配文件，覆盖文件树。
    /// 文件树因为文件夹层级导致匹配结果分散、呈现效率低；这里生成一张平铺列表，
    /// 每行带所在文件夹路径帮助定位。
    private var searchResultsSection: some View {
        let results = collectSearchResults()
        let rows = versionedSearchRows(results)
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("搜索结果")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.appMuted)
                if searchQuery.terms.count > 1 {
                    // 回显拆出来的条件，让用户确认“AI 菜花”被当成了两个词而不是一个
                    Text(searchQuery.displayText)
                        .font(.system(size: 11))
                        .foregroundColor(.appMuted.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text("\(results.count) 个文件")
                    .font(.system(size: 11))
                    .foregroundColor(.appMuted.opacity(0.7))
                Spacer(minLength: 0)
                Button("清除筛选") { clearFilters() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.appAccent)
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .padding(.bottom, 4)

            if results.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .light))
                    Text("没有匹配的文件")
                        .font(.system(size: 11))
                    if searchQuery.terms.count > 1 {
                        Text("\(searchQuery.terms.count) 个关键词需要同时命中")
                            .font(.system(size: 10.5))
                            .foregroundColor(.appMuted.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18)
                    }
                }
                .foregroundColor(.appMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                Spacer()
            } else {
                SidebarScrollView(
                    content: VStack(spacing: 0) {
                        ForEach(rows) { row in
                            LibraryFileRow(
                                file: row.file,
                                depth: 0,
                                sourceFolderID: row.sourceFolderID,
                                renameRowID: "",
                                isSelected: selectedURL?.standardizedFileURL == row.file.sourceURL.standardizedFileURL,
                                isKeyboardFocused: keyboardFocusedURL == row.file.sourceURL.standardizedFileURL,
                                onSelect: { selectedURL = $0 },
                                onRemove: row.sourceFolderID.map { folderID in
                                    { LibraryFolders.removeFile(row.file.id, from: folderID, in: &libraryFolders) }
                                },
                                isPinned: pinnedURLs.contains(row.file.sourceURL.standardizedFileURL),
                                onNewTag: beginCreatingTag,
                                onMetadataChanged: refreshMetadata,
                                onTogglePin: togglePin,
                                onRenameFile: { _, _ in },
                                renamingFileURL: nil,
                                renamingFileRowID: nil,
                                fileRenameName: .constant(""),
                                onRenameCommit: { _ in },
                                onRenameCancel: {},
                                onRequestDelete: requestSourceDeletion,
                                folderPath: row.folderPath,
                                allowsRename: false,
                                versionFamily: row.family
                            )
                        }
                    }
                    .padding(.horizontal, 4),
                    isHovered: isLibraryHovered
                )
                .onHover { isLibraryHovered = $0 }
            }
        }
    }

    private var searchAndFilterSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.appMuted)
                    TextField("筛选文件...", text: $filterText)
                        .font(.system(size: 12))
                        .foregroundColor(.appText)
                        .textFieldStyle(.plain)
                        .focused($isFilterFocused)
                        .help("多个关键词用空格分隔，需要全部命中；关键词可以落在文件名上，也可以落在它所在的文件夹名上")
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

                filterIconButton(
                    systemName: "square.grid.2x2",
                    isActive: selectedFormat != nil,
                    tooltip: "格式筛选"
                ) { isFormatFilterPresented.toggle() }
                .popover(isPresented: $isFormatFilterPresented, arrowEdge: .bottom) {
                    formatFilterPopover
                }

                filterIconButton(
                    systemName: "tag",
                    isActive: selectedTag != nil,
                    tooltip: "标签筛选"
                ) { isTagFilterPresented.toggle() }
                .popover(isPresented: $isTagFilterPresented, arrowEdge: .bottom) {
                    tagFilterPopover
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if selectedFormat != nil || selectedTag != nil {
                activeFilterChips
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }
        }
    }

    /// Small icon toggle button that presents a filter popover.
    private func filterIconButton(
        systemName: String,
        isActive: Bool,
        tooltip: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isActive ? .appAccent : .appMuted)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? Color.appAccentDimmed : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    /// Chips showing the active format/tag filters, each removable.
    private var activeFilterChips: some View {
        HStack(spacing: 4) {
            if let format = selectedFormat {
                filterChip(label: "格式: \(format.rawValue)") { selectedFormat = nil }
            }
            if let tag = selectedTag {
                filterChip(label: "标签: \(tag)") { selectedTag = nil }
            }
            Spacer(minLength: 0)
        }
    }

    private func filterChip(label: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.appAccent)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.appAccent)
            }
            .buttonStyle(.plain)
            .help("清除该筛选")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.appAccentDimmed)
        .clipShape(Capsule())
    }

    /// Popover content for the format filter.
    private var formatFilterPopover: some View {
        VStack(alignment: .leading, spacing: 2) {
            FormatRow(
                label: "全部",
                icon: "default",
                count: allDisplayedURLs.count,
                isSelected: selectedFormat == nil
            ) {
                selectedFormat = nil
                isFormatFilterPresented = false
            }

            ForEach(FileFormat.allCases, id: \.self) { format in
                let count = allDisplayedURLs.filter { FileFormat.for($0) == format }.count
                if count > 0 {
                    FormatRow(
                        label: format.rawValue,
                        icon: format.icon,
                        count: count,
                        isSelected: selectedFormat == format
                    ) {
                        selectedFormat = selectedFormat == format ? nil : format
                        isFormatFilterPresented = false
                    }
                }
            }
        }
        .padding(6)
        .frame(width: 180)
    }

    /// Popover content for the tag filter.
    private var tagFilterPopover: some View {
        VStack(alignment: .leading, spacing: 2) {
            TagRow(
                label: "全部",
                count: allDisplayedURLs.count,
                isSelected: selectedTag == nil,
                action: {
                    selectedTag = nil
                    isTagFilterPresented = false
                }
            )

            ForEach(FileTags.allTags(), id: \.self) { tag in
                let count = allDisplayedURLs.filter { FileTags.tags(for: $0).contains(tag) }.count
                if count > 0 {
                    TagRow(
                        label: tag,
                        count: count,
                        isSelected: selectedTag == tag,
                        action: {
                            selectedTag = selectedTag == tag ? nil : tag
                            isTagFilterPresented = false
                        }
                    )
                }
            }
        }
        .padding(6)
        .frame(width: 180)
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
                                    renameRowID: "recent:\(url.standardizedFileURL.path)",
                                    renamingFileURL: renamingFileURL,
                                    renamingFileRowID: renamingFileRowID,
                                    fileRenameName: $fileRenameName,
                                    onRenameCommit: commitRenamingFile,
                                    onRenameCancel: cancelRenamingFile,
                                    action: { selectedURL = url }
                                )
                                .contextMenu { recentContextMenu(for: url, rowID: "recent:\(url.standardizedFileURL.path)") }
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

    private func folderIDs(in folder: LibraryFolder) -> Set<UUID> {
        Set([folder.id]).union(folder.folders.reduce(into: Set<UUID>()) { ids, child in
            ids.formUnion(folderIDs(in: child))
        })
    }

    private func isSystemInbox(_ folder: LibraryFolder) -> Bool {
        folder.name == "未分类" && folder.folders.isEmpty
    }

    /// 逐级下钻时带着「沿途文件夹已经满足掉哪几个关键词」，
    /// 所以「AI 菜花」在 `菜花 · AI 销售` 里能整体命中，在别处需要两个词各有着落。
    private func filterFolder(_ folder: LibraryFolder, satisfiedByAncestors: Set<Int>) -> LibraryFolder? {
        let satisfied = satisfiedByAncestors.union(searchQuery.satisfied(by: folder.name))
        let folderMatchesQuery = !searchQuery.isEmpty && searchQuery.isFullySatisfied(by: satisfied)

        let files = folder.files.filter { file in
            let matchesText = searchQuery.matches(fileName: file.name, satisfiedByPath: satisfied)
            let matchesFormat = selectedFormat == nil || FileFormat.for(file.sourceURL) == selectedFormat
            let matchesTag = selectedTag == nil || FileTags.tags(for: file.sourceURL).contains(selectedTag!)
            return matchesText && matchesFormat && matchesTag
        }
        let children = folder.folders.compactMap {
            filterFolder($0, satisfiedByAncestors: satisfied)
        }

        let hasAttributeFilter = selectedFormat != nil || selectedTag != nil
        guard (!hasAttributeFilter && folderMatchesQuery) || !files.isEmpty || !children.isEmpty else { return nil }
        return LibraryFolder(id: folder.id, name: folder.name, sourcePath: folder.sourcePath,
                             folders: children, files: files)
    }

    /// 一个搜索结果条目：匹配的文件 + 它在库中的文件夹路径（用于扁平列表定位）。
    private struct SearchResultItem: Identifiable {
        var id: UUID { file.id }
        let file: LibraryFile
        let folderPath: String?
        /// nil = live 文件夹（归档目录）中的文件，不隶属于虚拟文件树。
        let sourceFolderID: UUID?
    }

    /// 收集所有匹配当前搜索/筛选条件的文件，扁平展开（不保留文件夹层级）。
    /// 搜索结果先按磁盘目录分桶再收成版本行：跨目录的同名文件不是同一份产物。
    private func versionedSearchRows(_ results: [SearchResultItem]) -> [VersionedSearchRow] {
        var order: [String] = []
        var buckets: [String: [SearchResultItem]] = [:]
        for item in results {
            let key = item.file.sourceURL.deletingLastPathComponent().path
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(item)
        }
        return order.flatMap { key -> [VersionedSearchRow] in
            let items = buckets[key] ?? []
            guard let representative = items.first else { return [] }
            return versionedRows(items.map(\.file)).map { row in
                VersionedSearchRow(
                    file: row.file,
                    family: row.family,
                    sourceFolderID: representative.sourceFolderID,
                    folderPath: representative.folderPath
                )
            }
        }
    }

    private func collectSearchResults() -> [SearchResultItem] {
        var results: [SearchResultItem] = []

        func walk(_ folder: LibraryFolder, path: [String], satisfiedByAncestors: Set<Int>) {
            let isInbox = isSystemInbox(folder)
            let isLive = folder.sourcePath != nil
            // 关键词落在文件夹名上时，该文件夹（任意层级）下的文件也算命中
            let satisfied = satisfiedByAncestors.union(searchQuery.satisfied(by: folder.name))
            for file in folder.files {
                let matchesText = searchQuery.matches(fileName: file.name, satisfiedByPath: satisfied)
                let matchesFormat = selectedFormat == nil || FileFormat.for(file.sourceURL) == selectedFormat
                let matchesTag = selectedTag == nil || FileTags.tags(for: file.sourceURL).contains(selectedTag!)
                guard matchesText && matchesFormat && matchesTag else { continue }
                // “未分类”在树中是根级文件，视觉上不显示路径
                let displayPath = isInbox ? nil : path.joined(separator: " / ")
                results.append(SearchResultItem(
                    file: file,
                    folderPath: displayPath,
                    sourceFolderID: isLive ? nil : folder.id
                ))
            }
            for child in folder.folders {
                walk(child, path: path + [child.name], satisfiedByAncestors: satisfied)
            }
        }

        for folder in libraryFolders {
            walk(folder, path: [folder.name], satisfiedByAncestors: [])
        }
        for mount in mounts.folders {
            walk(mount, path: [mount.name], satisfiedByAncestors: [])
        }

        return results.sorted {
            $0.file.name.localizedStandardCompare($1.file.name) == .orderedAscending
        }
    }

    private func clearFilters() {
        filterText = ""
        selectedFormat = nil
        selectedTag = nil
    }

    private func loadExpansionState() {
        let state = SidebarExpansionStore.load()
        isPinnedExpanded = state.isPinnedExpanded
        isLibraryExpanded = state.isLibraryExpanded
        isRecentExpanded = state.isRecentExpanded
        collapsedFolderIDs = state.collapsedFolderIDs
    }

    private var expansionState: SidebarExpansionState {
        SidebarExpansionState(
            isPinnedExpanded: isPinnedExpanded,
            isLibraryExpanded: isLibraryExpanded,
            isRecentExpanded: isRecentExpanded,
            collapsedFolderIDs: collapsedFolderIDs
        )
    }

    private func beginCreatingTag(for url: URL) {
        pendingTagURL = url
        newTagName = ""
        showNewTagAlert = true
    }

    private func refreshMetadata() {
        tagVersion = UUID()
    }

    private func requestSourceDeletion(for url: URL) {
        filePendingDeletion = url
    }

    private func beginRenamingFile(_ url: URL, rowID: String) {
        renamingFileURL = url.standardizedFileURL
        renamingFileRowID = rowID
        fileRenameName = url.lastPathComponent
    }

    private func commitRenamingFile(_ url: URL) {
        renameSourceFile(url, to: fileRenameName)
        renamingFileURL = nil
        renamingFileRowID = nil
    }

    private func cancelRenamingFile() {
        renamingFileURL = nil
        renamingFileRowID = nil
    }

    private func renameSourceFile(_ url: URL, to proposedName: String) {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !name.contains("/"),
              name != ".",
              name != ".."
        else {
            NSSound.beep()
            return
        }

        let renamedURL = url.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL
        guard renamedURL != url.standardizedFileURL else { return }
        guard !FileManager.default.fileExists(atPath: renamedURL.path) else {
            NSSound.beep()
            return
        }

        do {
            try FileManager.default.moveItem(at: url, to: renamedURL)
            LibraryFolders.replaceFileURL(url, with: renamedURL, in: &libraryFolders)
            FileHistory.replace(url, with: renamedURL)
            recentFiles = FileHistory.load()
            PinnedFiles.replace(url, with: renamedURL)
            pinnedURLs = PinnedFiles.load()
            FileTags.replaceURL(url, with: renamedURL)
            if selectedURL?.standardizedFileURL == url.standardizedFileURL { selectedURL = renamedURL }
            refreshMetadata()
        } catch {
            NSSound.beep()
        }
    }

    private func deleteSourceFile(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            LibraryFolders.removeFile(at: url, in: &libraryFolders)
            FileHistory.remove(url)
            recentFiles = FileHistory.load()
            PinnedFiles.remove(url)
            pinnedURLs = PinnedFiles.load()
            FileTags.removeAllTags(from: url)
            if selectedURL?.standardizedFileURL == url.standardizedFileURL { selectedURL = nil }
            refreshMetadata()
        } catch {
            NSSound.beep()
        }
    }

    private func addSingleFile() {
        guard let url = FileDropDelegate.openSingleFilePanel() else { return }
        Task {
            let imported = await Task.detached { LibraryFolders.prepareImport([url]) }.value
            await MainActor.run {
                LibraryFolders.apply(imported, into: &libraryFolders)
            }
        }
    }

    private func addExistingFolder() {
        guard let url = FileDropDelegate.openDirectoryPanel() else { return }
        Task {
            let imported = await Task.detached { LibraryFolders.prepareImport([url]) }.value
            await MainActor.run {
                LibraryFolders.apply(imported, into: &libraryFolders)
            }
        }
    }

    private func beginCreatingFolder() {
        renamingFolderID = nil
        newFolderParentID = nil
        folderName = ""
        showFolderNameAlert = true
    }

    @ViewBuilder
    private func recentContextMenu(for url: URL, rowID: String) -> some View {
        FileItemContextMenu(
            url: url,
            isPinned: pinnedURLs.contains(url.standardizedFileURL),
            onNewTag: beginCreatingTag,
            onMetadataChanged: refreshMetadata,
            onTogglePin: togglePin,
            onRenameFile: { _ in beginRenamingFile(url, rowID: rowID) },
            onRequestDelete: requestSourceDeletion,
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
        let includesExternalFile = providers.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }

        if !includesExternalFile, let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(libraryFileDragType.identifier)
        }) {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let string = item as? String else { return }
                DispatchQueue.main.async {
                    if let payload = LibraryFileDragPayload.from(string) {
                        moveLibraryFile(payload, into: folderID)
                    } else if let payload = LibraryFolderDragPayload.from(string) {
                        moveLibraryFolder(payload, into: folderID)
                    }
                }
            }
            return true
        }

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

    private func moveLibraryFile(_ payload: LibraryFileDragPayload, into folderID: UUID) {
        LibraryFolders.moveFile(
            payload.fileID,
            from: payload.sourceFolderID,
            to: folderID,
            in: &libraryFolders
        )
    }

    private func moveLibraryFolder(_ payload: LibraryFolderDragPayload, into folderID: UUID) {
        LibraryFolders.moveFolder(
            payload.folderID,
            from: payload.sourceParentID,
            to: folderID,
            in: &libraryFolders
        )
    }

    private func handleDropIntoRoot(_ providers: [NSItemProvider]) -> Bool {
        let includesExternalFile = providers.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }

        if !includesExternalFile, let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(libraryFileDragType.identifier)
        }) {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let string = item as? String else { return }
                DispatchQueue.main.async {
                    if let payload = LibraryFileDragPayload.from(string) {
                        LibraryFolders.moveFileToInbox(
                            payload.fileID,
                            from: payload.sourceFolderID,
                            in: &libraryFolders
                        )
                    } else if let payload = LibraryFolderDragPayload.from(string) {
                        LibraryFolders.moveFolderToRoot(
                            payload.folderID,
                            from: payload.sourceParentID,
                            in: &libraryFolders
                        )
                    }
                }
            }
            return true
        }

        return handleDrop(providers)
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

/// Keeps arrow/Enter/Esc navigation out of the large SwiftUI sidebar expression.
private struct SidebarKeyboardHandler: NSViewRepresentable {
    let urls: [URL]
    @Binding var focusedURL: URL?
    let onOpen: (URL) -> Void
    let onClear: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.update(urls: urls, focusedURL: $focusedURL, onOpen: onOpen, onClear: onClear)
        context.coordinator.install()
        // 必须用不吃事件的宿主：它盖在整个侧边栏上，普通 NSView 会让
        // 折叠标题、行选中、右键菜单、拖拽全部点不动。
        return EventPassthroughView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(urls: urls, focusedURL: $focusedURL, onOpen: onOpen, onClear: onClear)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        private var monitor: Any?
        private var urls: [URL] = []
        private var focusedURL: Binding<URL?>?
        private var onOpen: ((URL) -> Void)?
        private var onClear: (() -> Void)?

        func update(urls: [URL], focusedURL: Binding<URL?>, onOpen: @escaping (URL) -> Void, onClear: @escaping () -> Void) {
            self.urls = urls
            self.focusedURL = focusedURL
            self.onOpen = onOpen
            self.onClear = onClear
            if let current = focusedURL.wrappedValue, !urls.contains(current) {
                focusedURL.wrappedValue = urls.first
            } else if focusedURL.wrappedValue == nil, !urls.isEmpty {
                focusedURL.wrappedValue = urls.first
            }
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, !self.urls.isEmpty,
                      !event.modifierFlags.contains(.command),
                      !event.modifierFlags.contains(.control) else { return event }
                let index = self.focusedURL?.wrappedValue.flatMap { self.urls.firstIndex(of: $0) }
                switch event.keyCode {
                case 125, 126:
                    let delta = event.keyCode == 125 ? 1 : -1
                    let base = index ?? (delta > 0 ? -1 : 0)
                    let next = min(max(base + delta, 0), self.urls.count - 1)
                    self.focusedURL?.wrappedValue = self.urls[next]
                    return nil
                case 36:
                    if let url = self.focusedURL?.wrappedValue { self.onOpen?(url); return nil }
                case 53:
                    self.onClear?()
                    return nil
                default:
                    break
                }
                return event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { remove() }
    }
}

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
    let onRenameFile: (URL, String) -> Void
    @Binding var collapsedFolderIDs: Set<UUID>
    let renamingFileURL: URL?
    let renamingFileRowID: String?
    @Binding var fileRenameName: String
    let onRenameCommit: (URL) -> Void
    let onRenameCancel: () -> Void
    let onRequestDelete: (URL) -> Void
    let liveFolderIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(folders) { folder in
                LibraryFolderBranch(
                    folder: folder,
                    parentFolderID: nil,
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
                    onTogglePin: onTogglePin,
                    onRenameFile: onRenameFile,
                    collapsedFolderIDs: $collapsedFolderIDs,
                    renamingFileURL: renamingFileURL,
                    renamingFileRowID: renamingFileRowID,
                    fileRenameName: $fileRenameName,
                    onRenameCommit: onRenameCommit,
                    onRenameCancel: onRenameCancel,
                    onRequestDelete: onRequestDelete,
                    liveFolderIDs: liveFolderIDs
                )
            }
        }
    }
}

private struct LibraryFolderBranch: View {
    let folder: LibraryFolder
    let parentFolderID: UUID?
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
    let onRenameFile: (URL, String) -> Void
    @Binding var collapsedFolderIDs: Set<UUID>
    let renamingFileURL: URL?
    let renamingFileRowID: String?
    @Binding var fileRenameName: String
    let onRenameCommit: (URL) -> Void
    let onRenameCancel: () -> Void
    let onRequestDelete: (URL) -> Void
    let liveFolderIDs: Set<UUID>
    /// 版本选择是跨行共享的状态：某一族切了版本，树里展示它的那一行要跟着重算。
    @ObservedObject private var versionSelection = VersionSelectionStore.shared
    @State private var isHovering = false
    @State private var isDropTargeted = false

    /// 归档目录这类 live 文件夹：只做展示，不参与虚拟文件树的搬移、改名或删除。
    private var isLive: Bool { liveFolderIDs.contains(folder.id) }

    private var hasExpandableContent: Bool {
        !folder.folders.isEmpty || !folder.files.isEmpty
    }

    private var isExpanded: Bool {
        !collapsedFolderIDs.contains(folder.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
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
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .padding(.leading, 10 + CGFloat(depth) * 22)
            .padding(.trailing, 10)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isDropTargeted ? Color.appAccent.opacity(0.2) : (isHovering ? Color.appHoverBg : .clear))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard hasExpandableContent else { return }
                if isExpanded {
                    collapsedFolderIDs.insert(folder.id)
                } else {
                    collapsedFolderIDs.remove(folder.id)
                }
            }
            .onDrag {
                guard !isLive else { return NSItemProvider() }
                return LibraryFolderDragPayload(
                    folderID: folder.id,
                    sourceParentID: parentFolderID
                ).itemProvider()
            }
            .onHover { isHovering = $0 }
            .help(isLive ? (folder.sourcePath ?? folder.name) : "单击展开或折叠；拖拽移动文件夹")
            .onDrop(of: [libraryFileDragType, .fileURL], isTargeted: $isDropTargeted) { providers, _ in
                guard !isLive else { return false }
                return onImportIntoFolder(folder.id, providers)
            }

            if isExpanded {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(folder.folders) { child in
                    LibraryFolderBranch(
                        folder: child,
                        parentFolderID: folder.id,
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
                        onTogglePin: onTogglePin,
                        onRenameFile: onRenameFile,
                        collapsedFolderIDs: $collapsedFolderIDs,
                        renamingFileURL: renamingFileURL,
                        renamingFileRowID: renamingFileRowID,
                        fileRenameName: $fileRenameName,
                        onRenameCommit: onRenameCommit,
                        onRenameCancel: onRenameCancel,
                        onRequestDelete: onRequestDelete,
                        liveFolderIDs: liveFolderIDs
                    )
                }
                ForEach(versionedRows(folder.files)) { row in
                    LibraryFileRow(
                        file: row.file,
                        depth: depth + 1,
                        sourceFolderID: isLive ? nil : folder.id,
                        renameRowID: "library:\(row.file.id.uuidString)",
                        isSelected: selectedURL?.standardizedFileURL == row.file.sourceURL.standardizedFileURL,
                        onSelect: onSelectFile,
                        onRemove: isLive ? nil : { onRemoveFile(folder.id, row.file.id) },
                        isPinned: pinnedURLs.contains(row.file.sourceURL.standardizedFileURL),
                        onNewTag: onNewTag,
                        onMetadataChanged: onMetadataChanged,
                        onTogglePin: onTogglePin,
                        onRenameFile: onRenameFile,
                        renamingFileURL: renamingFileURL,
                        renamingFileRowID: renamingFileRowID,
                        fileRenameName: $fileRenameName,
                        onRenameCommit: onRenameCommit,
                        onRenameCancel: onRenameCancel,
                        onRequestDelete: onRequestDelete,
                        versionFamily: row.family
                    )
                }
            }
            }
        }
        .contextMenu {
            // 访达入口对 live 与虚拟文件夹一视同仁：能不能去由 finderLocation 决定，
            // 去不了就干脆不出现，不做一个点了没反应的按钮。
            if let location = folder.finderLocation {
                Button("在访达中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([location])
                }
                if !isLive { Divider() }
            }
            if !isLive {
                Button("新建子文件夹") { onCreateChildFolder(folder) }
                Button("重命名") { onRenameFolder(folder) }
                Divider()
                Button("删除文件夹", role: .destructive) { onRemoveFolder(folder) }
            }
        }
    }
}

/// 一个版本族的入口：行上显示版本数，点开在版本之间切换。
///
/// 只对多成员族出现。「这一行藏着别的版本」是关于行本身的事实，不是悬停才知道的操作提示，
/// 所以常显；颜色保持中性，只有用户钉住的不是最新版时才用强调色提醒。
private struct VersionChip: View {
    let family: VersionFamily
    let current: LibraryFile
    let onPick: (LibraryFile) -> Void
    let onReset: () -> Void

    @State private var isPresented = false

    /// 钉住的版本不是最新那一版——否则用户不知道自己在看旧的。
    private var isHeld: Bool { current.id != family.latest.id }

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 2) {
                Text("\(family.members.count) 版")
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .foregroundColor(isHeld ? .appAccent : .appMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.appHoverBg))
        }
        .buttonStyle(.plain)
        .help(isHeld
              ? "共 \(family.members.count) 个版本，当前钉在 \(current.name)"
              : "共 \(family.members.count) 个版本，当前是最新的一版")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) { versionList }
    }

    private var versionList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(family.name)
                .font(.system(size: 10.5))
                .foregroundColor(.appMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
                .padding(.bottom, 3)

            ForEach(Array(family.members.reversed())) { member in
                Button {
                    onPick(member)
                    isPresented = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(member.id == current.id ? .appAccent : .clear)
                            .frame(width: 9)
                        Text(member.name)
                            .font(.system(size: 12))
                            .foregroundColor(member.isAvailable ? .appText : .appMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 10)
                        Text(Self.timestamp(of: member.sourceURL))
                            .font(.system(size: 10.5))
                            .foregroundColor(.appMuted)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if isHeld {
                Divider().padding(.vertical, 2)
                Button {
                    onReset()
                    isPresented = false
                } label: {
                    Text("回到最新版本")
                        .font(.system(size: 11))
                        .foregroundColor(.appAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(width: 300)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private static func timestamp(of url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let date = values?.contentModificationDate else { return "" }
        return timestampFormatter.string(from: date)
    }
}

private struct LibraryFileRow: View {
    let file: LibraryFile
    let depth: Int
    let sourceFolderID: UUID?
    let renameRowID: String
    let isSelected: Bool
    var isKeyboardFocused: Bool = false
    /// 当前行展示的文件：版本族里就是当前被选中的那一版。
    let onSelect: (URL) -> Void
    let onRemove: (() -> Void)?
    let isPinned: Bool
    let onNewTag: (URL) -> Void
    let onMetadataChanged: () -> Void
    let onTogglePin: (URL) -> Void
    let onRenameFile: (URL, String) -> Void
    let renamingFileURL: URL?
    let renamingFileRowID: String?
    @Binding var fileRenameName: String
    let onRenameCommit: (URL) -> Void
    let onRenameCancel: () -> Void
    let onRequestDelete: (URL) -> Void
    /// 搜索结果模式下显示所在文件夹路径；nil = 文件树模式（只显示名称）。
    var folderPath: String? = nil
    /// false 时禁用行内重命名（搜索结果行回到文件树中重命名）。
    var allowsRename: Bool = true
    /// 非 nil 表示这一行代表一个版本族，行内可以切换版本。
    var versionFamily: VersionFamily? = nil
    @ObservedObject private var versionSelection = VersionSelectionStore.shared
    @State private var isHovering = false
    @FocusState private var isRenameFieldFocused: Bool

    private var isRenaming: Bool {
        allowsRename
            && renamingFileURL?.standardizedFileURL == file.sourceURL.standardizedFileURL
            && renamingFileRowID == renameRowID
    }

    /// 文件名没信息量时（`preview (3).html`）用内容里的标题顶上；只读，不改磁盘。
    private var displayName: String { DocumentTitles.displayName(of: file.sourceURL) }

    /// 副标题行：还原出的名字旁边必须还能看到真实文件名（否则找不到磁盘上的哪个文件），
    /// 搜索结果里再补上所在文件夹。
    private var secondaryLine: String? {
        var parts: [String] = []
        if displayName != file.name { parts.append(file.name) }
        if let folderPath, !folderPath.isEmpty { parts.append(folderPath) }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    /// contextMenu 的重命名回调；搜索结果模式（allowsRename=false）不显示重命名。
    private var contextMenuRenameHandler: ((URL) -> Void)? {
        guard allowsRename else { return nil }
        return { _ in onRenameFile(file.sourceURL, renameRowID) }
    }

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
            if isRenaming {
                TextField("文件名", text: $fileRenameName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.appText)
                    .focused($isRenameFieldFocused)
                    .onAppear { isRenameFieldFocused = true }
                    .onSubmit { onRenameCommit(file.sourceURL) }
                    .onExitCommand { onRenameCancel() }
                    .onChange(of: isRenameFieldFocused) { _, focused in
                        if !focused && isRenaming { onRenameCancel() }
                    }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName)
                        .font(.system(size: 13))
                        .foregroundColor(file.isAvailable ? .appText : .appMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let secondaryLine {
                        Text(secondaryLine)
                            .font(.system(size: 10.5))
                            .foregroundColor(.appMuted.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer(minLength: 0)

            if let versionFamily, versionFamily.isFamily {
                VersionChip(
                    family: versionFamily,
                    current: file,
                    onPick: { picked in
                        versionSelection.choose(picked.name, for: versionFamily.id)
                        onSelect(picked.sourceURL)
                    },
                    onReset: { versionSelection.choose(nil, for: versionFamily.id) }
                )
            }

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
                .fill(isSelected ? Color.appSelectedBg : (isKeyboardFocused || isHovering ? Color.appHoverBg : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if file.isAvailable { onSelect(file.sourceURL) }
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
                onRenameFile: contextMenuRenameHandler,
                onRequestDelete: onRequestDelete,
                removeTitle: onRemove == nil ? nil : "从列表移除",
                onRemove: onRemove
            )
        }
        .onDrag {
            guard let sourceFolderID else { return NSItemProvider() }
            return LibraryFileDragPayload(fileID: file.id, sourceFolderID: sourceFolderID).itemProvider()
        }
    }
}

private struct FileItemContextMenu: View {
    let url: URL
    let isPinned: Bool
    let onNewTag: (URL) -> Void
    let onMetadataChanged: () -> Void
    let onTogglePin: (URL) -> Void
    var onRenameFile: ((URL) -> Void)? = nil
    let onRequestDelete: (URL) -> Void
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
        Divider()
        if let onRenameFile {
            Button("重命名") { onRenameFile(url) }
        }
        Button("用默认程序打开") {
            NSWorkspace.shared.open(url)
        }
        Divider()
        Button("在访达中显示") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        Button("复制文件路径") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        }
        if let removeTitle, let onRemove {
            Divider()
            Button(removeTitle) { onRemove() }
        }
        Divider()
        Button("删除文件", role: .destructive) { onRequestDelete(url) }
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let url: URL
    let isSelected: Bool
    let isKeyboardFocused: Bool
    let onClearKeyboardFocus: () -> Void
    let renameRowID: String
    let renamingFileURL: URL?
    let renamingFileRowID: String?
    @Binding var fileRenameName: String
    let onRenameCommit: (URL) -> Void
    let onRenameCancel: () -> Void
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isRenameFieldFocused: Bool

    private var isRenaming: Bool {
        renamingFileURL?.standardizedFileURL == url.standardizedFileURL
            && renamingFileRowID == renameRowID
    }

    var body: some View {
        HStack(spacing: 6) {
            FileTypeIcon(
                url: url,
                color: isSelected ? .appAccent : .appMuted
            )

            if isRenaming {
                TextField("文件名", text: $fileRenameName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.appText)
                    .focused($isRenameFieldFocused)
                    .onAppear { isRenameFieldFocused = true }
                    .onSubmit { onRenameCommit(url) }
                    .onExitCommand { onRenameCancel() }
                    .onChange(of: isRenameFieldFocused) { _, focused in
                        if !focused && isRenaming { onRenameCancel() }
                    }
            } else {
                Text(url.lastPathComponent)
                    .font(.system(size: 13))
                    .foregroundColor(.appText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

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
