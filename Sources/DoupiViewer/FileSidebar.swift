import SwiftUI

/// Sidebar with recent files history.
struct FileSidebar: View {

    @Binding var selectedURL: URL?
    var refreshToken: Int = 0
    @State private var recentFiles: [URL] = []

    var body: some View {
        ZStack {
            Color.appInfoBg.ignoresSafeArea()
            List(selection: $selectedURL) {
                if !recentFiles.isEmpty {
                    Section {
                        ForEach(recentFiles, id: \.self) { url in
                            SidebarFileRow(url: url, isSelected: selectedURL == url)
                                .tag(url)
                                .contextMenu {
                                    Button("移除") {
                                        removeFromRecent(url)
                                    }
                                }
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        Text("最近打开")
                            .font(.appSmall)
                            .fontWeight(.semibold)
                            .foregroundColor(.appMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 24, weight: .light))
                                .foregroundColor(.appMuted)
                            Text("打开文件即可在此看到记录")
                                .font(.system(size: 12))
                                .foregroundColor(.appMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 200)
        .onAppear {
            recentFiles = FileHistory.load()
        }
        .onChange(of: refreshToken) { _, _ in
            recentFiles = FileHistory.load()
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
    let isSelected: Bool

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
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var iconName: String {
        switch url.pathExtension.lowercased() {
        case "html", "htm":  return "globe"
        case "swift":        return "swift"
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
