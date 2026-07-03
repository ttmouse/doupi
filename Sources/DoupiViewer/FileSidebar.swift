import SwiftUI

/// Sidebar with a project file tree and recent files history.
struct FileSidebar: View {

    @Binding var selectedURL: URL?
    @State private var projectFiles: [FileNode] = []
    @State private var recentFiles: [URL] = FileHistory.load()

    private let projectRoot = URL(fileURLWithPath: "/Users/douba/Projects/doupi")

    var body: some View {
        List(selection: $selectedURL) {
            // ── Recent files ──
            if !recentFiles.isEmpty {
                Section("最近打开") {
                    ForEach(recentFiles, id: \.self) { url in
                        SidebarFileRow(url: url)
                            .tag(url)
                            .contextMenu {
                                Button("移除") {
                                    removeFromRecent(url)
                                }
                            }
                    }
                }
            }

            // ── Project files ──
            Section("项目文件") {
                ForEach(projectFiles) { node in
                    FileTreeRow(node: node, selectedURL: $selectedURL)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .onAppear { refreshProjectFiles() }
        .onChange(of: selectedURL) { _, newURL in
            if let url = newURL {
                FileHistory.add(url)
                recentFiles = FileHistory.load()
            }
        }
    }

    // MARK: - Helpers

    private func refreshProjectFiles() {
        Task {
            let files = await Task.detached(priority: .userInitiated) {
                FileNode.scan(self.projectRoot)
            }.value
            await MainActor.run {
                self.projectFiles = files
            }
        }
    }

    private func removeFromRecent(_ url: URL) {
        var urls = FileHistory.load()
        urls.removeAll { $0 == url }
        FileHistory.save(urls)
        recentFiles = urls
    }
}

// MARK: - File Tree Row

struct FileTreeRow: View {

    let node: FileNode
    @Binding var selectedURL: URL?
    @State private var isExpanded = false

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: $isExpanded) {
                if let children = node.children {
                    ForEach(children) { child in
                        FileTreeRow(node: child, selectedURL: $selectedURL)
                    }
                }
            } label: {
                Label(node.name, systemImage: isExpanded ? "folder.fill" : "folder")
                    .font(.system(size: 13))
                    .foregroundColor(.appText)
            }
        } else {
            SidebarFileRow(url: node.url)
                .tag(node.url)
                .onTapGesture { selectedURL = node.url }
        }
    }
}

// MARK: - Sidebar File Row

struct SidebarFileRow: View {

    let url: URL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundColor(iconColor)
                .frame(width: 16)

            Text(url.lastPathComponent)
                .font(.system(size: 13))
                .foregroundColor(.appText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch url.pathExtension.lowercased() {
        case "html", "htm": return "globe"
        case "swift":       return "swift"
        case "js", "ts", "tsx", "jsx": return "chevron.left.forwardslash.chevron.right"
        case "css", "scss", "less":  return "paintbrush"
        case "json":        return "curlybraces"
        case "md", "markdown": return "doc.text"
        case "png", "jpg", "jpeg", "gif", "webp": return "photo"
        case "yaml", "yml", "toml": return "gearshape"
        case "py":          return "play.rectangle"
        case "sh", "bash", "zsh": return "terminal"
        case "sql":         return "tablecells"
        default:            return "doc"
        }
    }

    private var iconColor: Color {
        switch url.pathExtension.lowercased() {
        case "html", "htm": return .orange
        case "swift":       return .orange
        case "js", "ts", "tsx", "jsx": return .yellow
        case "css", "scss", "less":  return .blue
        case "json":        return .purple
        case "md":          return .gray
        case "png", "jpg", "jpeg", "gif", "webp": return .green
        default:            return .appMuted
        }
    }
}
