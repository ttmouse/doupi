import SwiftUI
import WebKit

/// Renders markdown files as formatted HTML using an inline marked.js parser.
struct MarkdownView: NSViewRepresentable {
    let url: URL
    var searchQuery: String? = nil
    var searchAction: SearchAction? = nil

    /// Called when search results update: (matchCount, currentMatch).
    var onSearchUpdate: ((Int, Int) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(searchAction: searchAction)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let pref = WKWebpagePreferences()
        pref.allowsContentJavaScript = true
        config.defaultWebpagePreferences = pref

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let key = url.path
        guard context.coordinator.lastLoadKey != key else {
            // Store latest search query and try to apply
            context.coordinator.pendingSearchQuery = searchQuery
            context.coordinator.pendingOnUpdate = onSearchUpdate
            context.coordinator.applySearchIfReady()
            return
        }
        context.coordinator.lastLoadKey = key
        context.coordinator.pageReady = false
        context.coordinator.pendingSearchQuery = searchQuery
        context.coordinator.pendingOnUpdate = onSearchUpdate
        context.coordinator.scheduleLoad(url: url, webView: webView)
    }

    // MARK: - HTML builder

    /// Builds a self-contained HTML document.
    /// - Parameter markdownJSON: The markdown content as a JSON-encoded string
    ///   literal (double-quoted, properly escaped), ready to embed directly in JS.
    fileprivate static func buildHTML(markdownJSON: String) -> String {
        let markedJS = MarkdownView.loadMarkedJS()

        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        *{box-sizing:border-box}body{margin:0;padding:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Noto Sans",Helvetica,Arial,sans-serif;font-size:16px;line-height:1.6;color:#1d1d1f;word-wrap:break-word;background:#f3f2ee}
        .markdown-body{max-width:900px;margin:0 auto;padding:40px 48px}
        .markdown-body h1,.markdown-body h2,.markdown-body h3,.markdown-body h4,.markdown-body h5,.markdown-body h6{margin-top:24px;margin-bottom:16px;font-weight:600;line-height:1.25}
        .markdown-body h1{font-size:2em;border-bottom:1px solid #ccc8c2;padding-bottom:.3em}
        .markdown-body h2{font-size:1.5em;border-bottom:1px solid #ccc8c2;padding-bottom:.3em}
        .markdown-body h3{font-size:1.25em}.markdown-body p{margin-top:0;margin-bottom:16px}
        .markdown-body a{color:#5d9a32;text-decoration:none}.markdown-body a:hover{text-decoration:underline}
        .markdown-body code{font-family:"SF Mono",Monaco,Menlo,Consolas,"Liberation Mono",monospace;font-size:85%;background:rgba(0,0,0,0.05);padding:.2em .4em;border-radius:3px}
        .markdown-body pre{background:rgba(0,0,0,0.05);padding:16px;border-radius:6px;overflow-x:auto}
        .markdown-body pre code{background:none;padding:0;font-size:85%}
        .markdown-body blockquote{margin:0;padding:0 1em;color:#787670;border-left:3px solid #ccc8c2}
        .markdown-body ul,.markdown-body ol{padding-left:2em;margin-bottom:16px}
        .markdown-body li+li{margin-top:.25em}
        .markdown-body table{border-collapse:collapse;width:100%;margin-bottom:16px}
        .markdown-body th,.markdown-body td{padding:6px 13px;border:1px solid #ccc8c2}
        .markdown-body th{font-weight:600;background:rgba(0,0,0,0.03)}
        .markdown-body img{max-width:100%}.markdown-body hr{border:0;height:1px;background:#ccc8c2;margin:24px 0}
        </style></head><body><div class="markdown-body" id="content"></div>
        <script>\(markedJS)</script>
        <script>document.getElementById('content').innerHTML=marked.parse(\(markdownJSON));</script>
        </body></html>
        """
    }

    private static func loadMarkedJS() -> String {
        guard let url = Bundle.module.url(forResource: "marked.min", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else {
            fputs("[MarkdownView] cannot load marked.min.js from bundle\n", stderr)
            return ""
        }
        return js
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadKey: String = ""
        var pageReady = false
        var matchCount = 0
        var currentIdx = 0
        var pendingSearchQuery: String? = nil
        var pendingOnUpdate: ((Int, Int) -> Void)? = nil
        weak var webView: WKWebView?
        let searchAction: SearchAction?
        private var loadTask: Task<Void, Never>?

        init(searchAction: SearchAction?) {
            self.searchAction = searchAction
        }

        deinit {
            loadTask?.cancel()
        }

        /// Read markdown file off main thread, then load HTML into WKWebView.
        func scheduleLoad(url: URL, webView: WKWebView) {
            loadTask?.cancel()
            loadTask = Task {
                let markdown: String? = await Task.detached(priority: .userInitiated) {
                    try? String(contentsOf: url, encoding: .utf8)
                }.value

                guard let md = markdown, !Task.isCancelled else { return }

                // Encode as JSON for safe JS embedding (prevents </script> injection)
                let encoder = JSONEncoder()
                guard let jsonData = try? encoder.encode(md),
                      let jsonString = String(data: jsonData, encoding: .utf8)
                else { return }

                let html = MarkdownView.buildHTML(markdownJSON: jsonString)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    webView.loadHTMLString(html, baseURL: nil)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(MarkdownView.searchJS)
            pageReady = true
            applySearchIfReady()
        }

        /// Try to execute the pending search query.
        func applySearchIfReady() {
            guard pageReady, let wv = webView else { return }
            let onUpdate = pendingOnUpdate

            if let q = pendingSearchQuery, !q.isEmpty {
                wv.evaluateJavaScript("doupiSearch('\(q.escapedForJS())')") { result, _ in
                    if let json = result as? String,
                       let data = json.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
                        onUpdate?(obj["count"] ?? 0, obj["current"] ?? 0)
                    }
                }
            } else if pendingSearchQuery?.isEmpty != false {
                wv.evaluateJavaScript("doupiSearch('')")
                onUpdate?(0, 0)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    // MARK: - Search JS (shared via SearchJS)

    fileprivate static let searchJS = SearchJS.injectionScript
}
