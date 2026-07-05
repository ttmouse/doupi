import SwiftUI
import UniformTypeIdentifiers

/// Main content area with sidebar + document viewer.
struct ContentView: View {

    @State private var fileURL: URL?
    @State private var fileInfo: FileInfo?
    @State private var isDragOver = false
    @State private var sidebarVisible = true
    @State private var eventMonitor: Any? = nil
    @State private var sidebarRefresh = 0

    // MARK: - Search

    @State private var search = SearchState()

    // MARK: - Body

    var body: some View {
        NavigationSplitView(
            sidebar: {
                if sidebarVisible {
                    FileSidebar(selectedURL: $fileURL, refreshToken: sidebarRefresh)
                        .onChange(of: fileURL) { _, newURL in
                            guard let url = newURL else { return }
                            loadFile(url: url)
                        }
                }
            },
            detail: {
                ZStack {
                    Color.appBackground.ignoresSafeArea()

                    if let info = fileInfo {
                        documentArea(info: info)
                    } else {
                        dropZone
                    }
                }
                .overlay(alignment: .top) {
                    VStack(spacing: 0) {
                        if fileInfo != nil {
                            infoBar
                        }
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
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    sidebarToggleButton
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
        )
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Sidebar toggle button

    private var sidebarToggleButton: some View {
        Button(action: { sidebarVisible.toggle() }) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.appMuted)
                .padding(6)
                .background(Color.appInfoBg.opacity(0.8))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(sidebarVisible ? "隐藏侧边栏" : "显示侧边栏")
        .padding(8)
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.appAccent.opacity(isDragOver ? 0.6 : 0.25), lineWidth: 2)
                    .shadow(color: Color.appAccent.opacity(isDragOver ? 0.4 : 0.15),
                            radius: isDragOver ? 30 : 12)

                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.appAccentDimmed.opacity(isDragOver ? 0.25 : 0.08))

                VStack(spacing: 14) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 44, weight: .light))
                        .foregroundColor(.appAccent)

                    Text("拖拽文件到此处\n或点击选择")
                        .multilineTextAlignment(.center)
                        .font(.system(size: 18, weight: .regular, design: .default))
                        .foregroundColor(.appMuted)
                        .lineSpacing(6)

                    Text("支持 HTML / 代码 / 图片 / 文本")
                        .font(.appSmall)
                        .foregroundColor(.appMuted.opacity(0.6))
                }
                .padding(40)
            }
            .frame(width: 340, height: 260)
            .onTapGesture { openFile() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appDropBg)
    }

    // MARK: - Document area

    private func documentArea(info: FileInfo) -> some View {
        let extraTop: CGFloat = search.isVisible ? 36 : 0
        let action = search.pendingAction
        // Clear the pending action so it's consumed exactly once
        DispatchQueue.main.async { search.pendingAction = nil }
        return DocumentView(
            info: info,
            searchQuery: search.isVisible ? search.query : nil,
            searchAction: action
        )
        .id(info.id)
        .padding(.top, 44 + extraTop)
    }

    // MARK: - Info bar

    private var infoBar: some View {
        HStack(spacing: 10) {
            if let info = fileInfo {
                Text(info.typeBadge)
                    .font(.appSmall)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appAccentDeep)
                    .cornerRadius(4)

                Text(info.name)
                    .font(.appTitle)
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
        .background(Color.appInfoBg)
    }

    // MARK: - Actions

    private func openFile() {
        guard let url = FileDropDelegate.openPanel() else { return }
        loadFile(url: url)
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
            if let url = await FileDropDelegate.handleDrop(providers) {
                await MainActor.run { loadFile(url: url) }
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
            return event
        }
    }
}
