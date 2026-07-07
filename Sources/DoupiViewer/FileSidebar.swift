import SwiftUI
import UniformTypeIdentifiers

/// Sidebar with recent files history.
struct FileSidebar: View {

    @Binding var selectedURL: URL?
    var refreshToken: Int = 0
    @State private var recentFiles: [URL] = []
    @State private var filterText = ""
    @State private var isDropTargeted = false
    @FocusState private var isFilterFocused: Bool

    /// External binding to focus filter from ContentView keyboard shortcut.
    var focusFilter: Binding<Bool>?

    private var filteredFiles: [URL] {
        filterText.isEmpty
            ? recentFiles
            : recentFiles.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(filterText) }
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

            if !recentFiles.isEmpty {
                List {
                    ForEach(filteredFiles, id: \.self) { url in
                        SidebarRow(url: url, isSelected: selectedURL == url) {
                            selectedURL = url
                        }
                        .contextMenu {
                            Button("移除") {
                                removeFromRecent(url)
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                    }
                    .onMove { source, destination in
                        var items = recentFiles
                        items.move(fromOffsets: source, toOffset: destination)
                        recentFiles = items
                        FileHistory.save(items)
                    }
                }
                .listStyle(.plain)
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
        .onChange(of: focusFilter?.wrappedValue) { _, focused in
            if focused == true {
                isFilterFocused = true
                focusFilter?.wrappedValue = false
            }
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
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
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
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(rowBackground)
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var rowBackground: Color {
        if isSelected { return .appSelectedBg }
        if isHovering { return .appHoverBg }
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
