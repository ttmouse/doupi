import SwiftUI

/// Dispatches to the correct renderer based on file type.
/// For code/text views, reads file content once (synchronously on first access),
/// then caches it so CodeView/MarkdownView are created immediately.
struct DocumentView: View {

    let info: FileInfo

    /// Passed through to WebView / CodeView for text search.
    var searchQuery: String? = nil
    var searchAction: SearchAction? = nil

    /// Called when search results update: (matchCount, currentMatch).
    var onSearchUpdate: ((Int, Int) -> Void)? = nil

    /// Read once on first body render — synchronous for small code/text files.
    /// Large files load in a fraction of a second; the trade-off is that
    /// the main thread is briefly occupied, but it guarantees CodeView exists
    /// and its WKWebView starts loading before any search can arrive.
    @State private var fileContent: String? = nil

    var body: some View {
        Group {
            if info.isHTML {
                htmlView
            } else if info.isMarkdown {
                markdownView
            } else if info.isTSX {
                tsxPreviewView
            } else if info.isCode {
                codeView
            } else if info.isImage {
                imageView
            } else if info.isPDF {
                pdfView
            } else if info.isText {
                textView
            } else {
                unsupportedView
            }
        }
        .task(id: info.url) {
            await loadContentIfNeeded()
        }
    }

    // MARK: - HTML (file URL loading so CSS/images work)

    private var htmlView: some View {
        let readRoot = info.url.deletingLastPathComponent()
        return WebView(
            fileURL: info.url,
            readAccessRoot: readRoot,
            searchQuery: searchQuery,
            searchAction: searchAction,
            onSearchUpdate: onSearchUpdate
        )
        .ignoresSafeArea()
    }

    // MARK: - Markdown (rendered via inline marked.js)

    private var markdownView: some View {
        MarkdownView(url: info.url,
                     searchQuery: searchQuery,
                     searchAction: searchAction,
                     onSearchUpdate: onSearchUpdate)
        .ignoresSafeArea()
    }

    // MARK: - TSX/JSX preview

    private var tsxPreviewView: some View {
        PreviewContainer(sourceURL: info.url,
                         searchQuery: searchQuery,
                         searchAction: searchAction,
                         onSearchUpdate: onSearchUpdate)
        .ignoresSafeArea()
    }

    // MARK: - Syntax-highlighted code

    @ViewBuilder
    private var codeView: some View {
        if let content = fileContent {
            CodeView(content: content, language: info.highlightLanguage,
                     searchQuery: searchQuery, searchAction: searchAction,
                     onSearchUpdate: onSearchUpdate)
        } else {
            CodeView(content: "", language: info.highlightLanguage,
                     searchQuery: searchQuery, searchAction: searchAction,
                     onSearchUpdate: onSearchUpdate)
        }
    }

    // MARK: - Image

    private var imageView: some View {
        ImageView(url: info.url)
    }

    // MARK: - PDF

    private var pdfView: some View {
        PDFViewer(url: info.url)
    }

    // MARK: - Plain text

    @ViewBuilder
    private var textView: some View {
        if let content = fileContent {
            ScrollView([.vertical, .horizontal]) {
                Text(content)
                    .font(.appCode)
                    .foregroundColor(.appText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .background(Color.appBackground)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
        }
    }

    // MARK: - Unsupported

    private var unsupportedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 48))
                .foregroundColor(.appMuted)
            Text("不支持的文件类型")
                .font(.appTitle)
                .foregroundColor(.appMuted)
            Text(".\(info.ext)")
                .font(.appBody)
                .foregroundColor(.appMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    // MARK: - Async loading

    private func loadContentIfNeeded() async {
        guard fileContent == nil, (info.isCode || info.isText) else { return }
        let url = info.url
        let content: String = await Task.detached(priority: .userInitiated) {
            (try? String(contentsOf: url, encoding: .utf8)) ?? "// 无法读取文件内容"
        }.value
        await MainActor.run {
            self.fileContent = content
        }
    }
}
