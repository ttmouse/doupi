import SwiftUI
import UniformTypeIdentifiers

/// Main content area with sidebar + document viewer.
struct ContentView: View {

    @EnvironmentObject private var openRouter: OpenFileRouter

    @State private var fileURL: URL?
    @State private var fileInfo: FileInfo?
    @State private var fileMonitor: FileChangeMonitor?
    @State private var fileRevision = 0
    @State private var fileUnavailable = false
    @State private var isDragOver = false
    @State private var sidebarVisible = true {
        didSet {
            if sidebarVisible {
                // 延迟直到侧边栏渲染完成，然后激活搜索框
                DispatchQueue.main.async {
                    sidebarFilterFocused = true
                }
            }
        }
    }
    @State private var eventMonitor: Any? = nil
    @State private var sidebarRefresh = 0
    @State private var sidebarFilterFocused = false

    // MARK: - Search

    @State private var search = SearchState()

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                ResizableSidebar {
                    FileSidebar(selectedURL: $fileURL, refreshToken: sidebarRefresh, focusFilter: $sidebarFilterFocused)
                        .background(Color.appInfoBg)
                        .preferredColorScheme(.light)
                        .onChange(of: fileURL) { _, newURL in
                            guard let url = newURL else { return }
                            loadFile(url: url)
                        }
                }

            }

            // Content area — width naturally excludes the sidebar when visible
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if let info = fileInfo {
                    VStack(spacing: 0) {
                        if search.isVisible {
                            SearchBar(
                                query: $search.query,
                                matchCount: search.matchCount,
                                currentMatch: search.currentMatch,
                                onNext: { navigateSearch(1) },
                                onPrev: { navigateSearch(-1) },
                                onClose: { resetSearch() }
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        documentArea(info: info)
                    }
                } else {
                    dropZone
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                handleDrop(providers)
            }
            .onAppear {
                if eventMonitor == nil {
                    eventMonitor = registerKeyboardShortcuts()
                }
                startFileMonitorIfNeeded()
                consumePendingOpenURL()
            }
            .onChange(of: openRouter.pendingURL) { _, _ in
                consumePendingOpenURL()
            }
            .onReceive(NotificationCenter.default.publisher(for: .doupiFileChanged)) { notification in
                guard let changedURL = notification.object as? URL,
                      changedURL.standardizedFileURL == fileURL?.standardizedFileURL
                else { return }
                refreshCurrentFile()
            }
            .onDisappear {
                fileMonitor?.stop()
                fileMonitor = nil
                if let monitor = eventMonitor {
                    NSEvent.removeMonitor(monitor)
                    eventMonitor = nil
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: sidebarVisible)
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 20) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.appSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isDragOver ? Color.appAccent : Color.appBorder, lineWidth: 1)
                )
                .overlay {
                    VStack(spacing: 14) {
                        Image(systemName: "doc.viewfinder")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(isDragOver ? .appAccent : .appMuted)

                        Text("拖拽文件到此处\n或点击选择")
                            .multilineTextAlignment(.center)
                            .font(.appDisplay)
                            .foregroundColor(.appText.opacity(0.8))
                            .lineSpacing(6)

                        Text("支持 HTML / 代码 / 图片 / 文本")
                            .font(.appSmall)
                            .foregroundColor(.appMuted)
                    }
                    .padding(40)
                }
                .frame(width: 360, height: 240)
                .onTapGesture { openFile() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appDropBg)
    }

    // MARK: - Document area

    @ViewBuilder
    private func documentArea(info: FileInfo) -> some View {
        if fileUnavailable {
            unavailableFileView(info: info)
        } else {
            // 故意不带 .id(info.id)：同一类文件之间切换时复用同一个渲染器。
            // 每次重建 WKWebView 要 ~90 ms，Markdown 还要重新内联 3.4 MB 渲染器。
            DocumentView(
                info: info,
                refreshToken: fileRevision,
                searchQuery: search.isVisible ? search.query : nil,
                searchCommand: search.pendingCommand,
                onSearchUpdate: { matchCount, currentMatch in
                    search.matchCount = matchCount
                    search.currentMatch = currentMatch
                }
            )
        }
    }

    private func unavailableFileView(info: FileInfo) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.badge.ellipsis")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.appMuted)
            Text("文件暂时不可用")
                .font(.appTitle)
                .foregroundColor(.appText)
            Text("“\(info.name)”已被删除或正在写入，恢复后会自动刷新")
                .font(.appBody)
                .foregroundColor(.appMuted)
                .multilineTextAlignment(.center)
            Text("⌘R 可手动检查")
                .font(.appSmall)
                .foregroundColor(.appMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    // MARK: - Info bar

    private var infoBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let info = fileInfo {
                    Text(info.typeBadge)
                        .font(.appSmall)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.appAccentDeep)
                        .cornerRadius(5)

                    Text(info.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.appText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Text(info.sizeFormatted)
                        .font(.appSmall)
                        .foregroundColor(.appMuted)

                    Button(action: closeFile) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.appMuted)
                    }
                    .buttonStyle(.plain)
                    .help("关闭文件")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.appSurface)

            Divider()
                .overlay(Color.appBorder)
        }
    }

    // MARK: - Actions

    private func openFile() {
        let urls = FileDropDelegate.openPanel()
        guard !urls.isEmpty else { return }
        Task {
            let imported = await Task.detached { LibraryFolders.prepareImport(urls) }.value
            let renderableURLs = imported.allFileURLs.filter { FileInfo.from(url: $0)?.isRenderable == true }
            var folders = LibraryFolders.load()
            LibraryFolders.apply(imported, into: &folders)
            sidebarRefresh += 1
            if let first = renderableURLs.first {
                loadFile(url: first)
            }
        }
    }

    private func closeFile() {
        fileMonitor?.stop()
        fileMonitor = nil
        fileURL = nil
        fileInfo = nil
        fileUnavailable = false
        resetSearch()
    }

    private func loadFile(url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard let info = FileInfo.from(url: standardizedURL), info.isRenderable else {
            fileMonitor?.stop()
            fileMonitor = nil
            fileURL = standardizedURL
            fileInfo = FileInfo.from(url: standardizedURL)
            fileUnavailable = !FileManager.default.fileExists(atPath: standardizedURL.path)
            return
        }

        let isSameFile = fileURL?.standardizedFileURL == standardizedURL
        fileURL = standardizedURL
        fileInfo = info
        fileUnavailable = !FileManager.default.fileExists(atPath: standardizedURL.path)
        if !isSameFile || fileMonitor?.url != standardizedURL {
            fileMonitor?.stop()
            fileMonitor = FileChangeMonitor(url: standardizedURL)
            fileMonitor?.start()
            fileRevision = 0
        }
        FileHistory.add(standardizedURL)
        sidebarRefresh += 1
    }

    private func startFileMonitorIfNeeded() {
        guard let url = fileURL,
              fileInfo?.isRenderable == true,
              fileMonitor == nil
        else { return }
        fileMonitor = FileChangeMonitor(url: url)
        fileMonitor?.start()
    }

    /// Re-reads metadata and nudges the current renderer without changing its identity.
    /// Web renderers use this token to reload or push content while restoring ScrollMemory.
    private func refreshCurrentFile() {
        guard let url = fileURL else { return }
        fileUnavailable = !FileManager.default.fileExists(atPath: url.path)
        fileInfo = FileInfo.from(url: url) ?? fileInfo
        fileRevision &+= 1
    }

    /// Loads a file URL delivered by the system ("Open With" / default app
    /// launch). Handles both cold start (view not yet mounted) and hot path.
    private func consumePendingOpenURL() {
        guard let url = openRouter.pendingURL else { return }
        openRouter.pendingURL = nil
        loadFile(url: url)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task {
            let droppedURLs = await FileDropDelegate.collectURLs(from: providers)
            guard !droppedURLs.isEmpty else { return }
            let imported = await Task.detached { LibraryFolders.prepareImport(droppedURLs) }.value
            let renderableURLs = imported.allFileURLs.filter { FileInfo.from(url: $0)?.isRenderable == true }
            await MainActor.run {
                var folders = LibraryFolders.load()
                LibraryFolders.apply(imported, into: &folders)
                sidebarRefresh += 1
                if let first = renderableURLs.first {
                    loadFile(url: first)
                }
            }
        }
        return true
    }

    // MARK: - Search navigation

    private func resetSearch() {
        search.isVisible = false
        search.query = ""
        search.matchCount = 0
        search.currentMatch = 0
        search.pendingCommand = nil
        // commandSeq 不重置：编号只能往前跑。否则关掉搜索再打开时新指令会撞上旧编号，
        // 被长驻页面当成“已经执行过”而丢掉。
    }

    private func navigateSearch(_ dir: Int) {
        // 每条指令都带新编号：长驻页面上靠编号判断「这是新的一次」，不然按一次 ⌘G
        // 会被每一次视图更新重新执行一遍。
        search.commandSeq += 1
        search.pendingCommand = SearchCommand(action: dir > 0 ? .next : .prev, id: search.commandSeq)
    }

    // MARK: - Keyboard shortcuts

    private func registerKeyboardShortcuts() -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // ⌘+⇧+F — focus sidebar filter
            if event.modifierFlags.contains(.command) && event.modifierFlags.contains(.shift) && event.keyCode == 3 {
                sidebarFilterFocused = true
                return nil
            }
            // ⌘+F — open/focus search
            if event.modifierFlags.contains(.command) && event.keyCode == 3 {
                search.isVisible = true
                search.query = ""
                return nil
            }
            // ⌘+G — next match
            if event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.shift) && event.keyCode == 5 {
                if search.isVisible && !search.query.isEmpty { search.currentMatch = min(search.currentMatch + 1, max(search.matchCount - 1, 0)) }
                navigateSearch(1)
                return nil
            }
            // ⌘+⇧+G — previous match
            if event.modifierFlags.contains(.command) && event.modifierFlags.contains(.shift) && event.keyCode == 5 {
                if search.isVisible && !search.query.isEmpty { search.currentMatch = max(search.currentMatch - 1, 0) }
                navigateSearch(-1)
                return nil
            }
            // Esc — close search
            if event.keyCode == 53 && search.isVisible {
                resetSearch()
                return nil
            }
            // ⌘+R — refresh the current file (manual fallback for missed filesystem events)
            if event.modifierFlags.contains(.command) && event.keyCode == 15,
               fileURL != nil {
                refreshCurrentFile()
                return nil
            }
            // ⌘+O — open file
            if event.modifierFlags.contains(.command) && event.keyCode == 31 {
                openFile()
                return nil
            }
            // ⌘+W — close file
            if event.modifierFlags.contains(.command) && event.keyCode == 13 {
                closeFile()
                return nil
            }
            // ⌘+B — toggle sidebar
            if event.modifierFlags.contains(.command) && event.keyCode == 11 {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sidebarVisible.toggle()
                }
                return nil
            }
            return event
        }
    }
}

private struct ResizableSidebar<Content: View>: View {
    let content: Content
    @AppStorage("DoupiSidebarWidth") private var storedWidth = 240.0
    @State private var width = 240.0

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            content
                .frame(width: width)
            SidebarResizeHandle(width: $width) {
                storedWidth = width
            }
        }
        .onAppear {
            width = min(480, max(180, storedWidth))
        }
    }
}

private struct SidebarResizeHandle: View {
    @Binding var width: Double
    let onResizeEnded: () -> Void
    @State private var dragStartWidth: Double?
    @State private var hasResizeCursor = false

    private let minimumWidth = 180.0
    private let maximumWidth = 480.0

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering && !hasResizeCursor {
                    NSCursor.resizeLeftRight.push()
                    hasResizeCursor = true
                } else if !hovering && hasResizeCursor {
                    NSCursor.pop()
                    hasResizeCursor = false
                }
            }
            .onDisappear {
                if hasResizeCursor { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartWidth == nil { dragStartWidth = width }
                        guard let dragStartWidth else { return }
                        width = min(maximumWidth, max(minimumWidth, dragStartWidth + value.translation.width))
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        onResizeEnded()
                    }
            )
    }
}
