import SwiftUI

/// Dispatches to the correct renderer based on file type.
struct DocumentView: View {

    let info: FileInfo
    /// Changes only when the user requests a refresh or the file watcher sees a change.
    var refreshToken: Int = 0

    /// Passed through to WebView / CodeView for text search.
    var searchQuery: String? = nil
    var searchCommand: SearchCommand? = nil

    /// Called when search results update: (matchCount, currentMatch).
    var onSearchUpdate: ((Int, Int) -> Void)? = nil

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
    }

    // MARK: - HTML (file URL loading so CSS/images work)

    private var htmlView: some View {
        let readRoot = info.url.deletingLastPathComponent()
        return WebView(
            fileURL: info.url,
            readAccessRoot: readRoot,
            contentKey: info.url.path,
            reloadToken: refreshToken,
            searchQuery: searchQuery,
            searchCommand: searchCommand
        )
        .ignoresSafeArea()
    }

    // MARK: - Markdown (rendered via inline marked.js)

    private var markdownView: some View {
        MarkdownView(url: info.url,
                     reloadToken: refreshToken,
                     searchQuery: searchQuery,
                     searchCommand: searchCommand)
        .ignoresSafeArea()
    }

    // MARK: - TSX/JSX preview

    private var tsxPreviewView: some View {
        PreviewContainer(sourceURL: info.url,
                         reloadToken: refreshToken,
                         searchQuery: searchQuery,
                         searchCommand: searchCommand)
        .ignoresSafeArea()
    }

    // MARK: - Syntax-highlighted code

    private var codeView: some View {
        let content = (try? String(contentsOf: info.url, encoding: .utf8)) ?? "// 无法读取文件内容"
        return CodeView(content: content, language: info.highlightLanguage,
                        contentKey: info.url.path, reloadToken: refreshToken,
                        searchQuery: searchQuery, searchCommand: searchCommand,
                        onSearchUpdate: onSearchUpdate)
    }

    // MARK: - Image

    private var imageView: some View {
        ImageView(url: info.url, reloadToken: refreshToken)
    }

    // MARK: - PDF

    private var pdfView: some View {
        PDFViewer(url: info.url, reloadToken: refreshToken)
    }

    // MARK: - Plain text

    private var textView: some View {
        let content = (try? String(contentsOf: info.url, encoding: .utf8)) ?? "无法读取文件内容"
        return ScrollView([.vertical, .horizontal]) {
            Text(content)
                .font(.appCode)
                .foregroundColor(.appText)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .background(Color.appBackground)
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
}
