import SwiftUI
import UniformTypeIdentifiers

/// Main content area with sidebar + document viewer.
struct ContentView: View {

    @State private var fileURL: URL?
    @State private var fileInfo: FileInfo?
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
                FileSidebar(selectedURL: $fileURL, refreshToken: sidebarRefresh, focusFilter: $sidebarFilterFocused)
                    .frame(width: 240)
                    .background(Color.appInfoBg)
                    .preferredColorScheme(.light)
                    .onChange(of: fileURL) { _, newURL in
                        guard let url = newURL else { return }
                        loadFile(url: url)
                    }

                Divider()
                    .overlay(Color.appBorder)
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
                                onClose: { search.close() }
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
                eventMonitor = registerKeyboardShortcuts()
            }
            .onDisappear {
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

    private func documentArea(info: FileInfo) -> some View {
        let action = search.pendingAction
        return DocumentView(
            info: info,
            searchQuery: search.isVisible ? search.query : nil,
            searchAction: action
        )
        .id(info.id)
        .onAppear {
            search.pendingAction = nil
        }
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
        FileHistory.bulkAdd(urls)
        sidebarRefresh += 1
        loadFile(url: urls[0])
    }

    private func closeFile() {
        fileURL = nil
        fileInfo = nil
        search.close()
    }

    private func loadFile(url: URL) {
        guard let info = FileInfo.from(url: url), info.isRenderable else {
            fileURL = url
            fileInfo = FileInfo.from(url: url)
            return
        }
        let isNew = !FileHistory.contains(url)
        fileURL = url
        fileInfo = info
        FileHistory.add(url)
        if isNew { sidebarRefresh += 1 }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task {
            let urls = await FileDropDelegate.collectRenderableFiles(from: providers)
            guard !urls.isEmpty else { return }
            FileHistory.bulkAdd(urls)
            await MainActor.run {
                sidebarRefresh += 1
                loadFile(url: urls[0])
            }
        }
        return true
    }

    // MARK: - Search navigation

    private func navigateSearch(_ dir: Int) {
        search.pendingAction = dir > 0 ? .next : .prev
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
                search.close()
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
