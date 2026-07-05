import SwiftUI

/// Sidebar with recent files history only.
struct FileSidebar: View {

    @Binding var selectedURL: URL?
    @State private var recentFiles: [URL] = FileHistory.load()

    var body: some View {
        List(selection: $selectedURL) {
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
            } else {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 28))
                            .foregroundColor(.appMuted)
                        Text("拖拽文件到此处预览")
                            .font(.system(size: 12))
                            .foregroundColor(.appMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .onChange(of: selectedURL) { _, newURL in
            if let _ = newURL {
                recentFiles = FileHistory.load()
            }
        }
    }

    // MARK: - Helpers

    private func removeFromRecent(_ url: URL) {
        var urls = FileHistory.load()
        urls.removeAll { $0 == url }
        FileHistory.save(urls)
        recentFiles = urls
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
