import SwiftUI

/// Dispatches to the correct renderer based on file type.
struct DocumentView: View {

    let info: FileInfo

    var body: some View {
        Group {
            if info.isHTML {
                htmlView
            } else if info.isTSX {
                tsxPreviewView
            } else if info.isCode {
                codeView
            } else if info.isImage {
                imageView
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
            readAccessRoot: readRoot
        )
    }

    // MARK: - TSX/JSX preview (compiled via esbuild -> file URL)

    private var tsxPreviewView: some View {
        PreviewContainer(sourceURL: info.url)
            .id(info.url)
    }

    // MARK: - Syntax-highlighted code

    private var codeView: some View {
        let content = (try? String(contentsOf: info.url, encoding: .utf8)) ?? "// 无法读取文件内容"
        return CodeView(content: content, language: info.highlightLanguage)
    }

    // MARK: - Image

    private var imageView: some View {
        ImageView(url: info.url)
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
