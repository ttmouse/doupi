import SwiftUI
import WebKit

// MARK: - Search action enum

/// Sent by the parent to navigate between search matches.
enum SearchAction: Equatable {
    case next
    case prev
}

/// Renders source code with syntax highlighting via highlight.js v11
/// inside a transparent-background WKWebView. Supports text search with
/// JS-based highlighting. Search functions from SearchJS.functionsJS
/// are embedded inline in the HTML template.
struct CodeView: NSViewRepresentable {

    let content: String
    let language: String

    /// When non-nil, the JS search highlighter is triggered.
    var searchQuery: String? = nil

    /// Called by the parent to navigate between matches.
    var searchAction: SearchAction? = nil

    /// Called when search results update: (matchCount, currentMatch).
    var onSearchUpdate: ((Int, Int) -> Void)? = nil

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> WKWebView {
        let config = buildConfig()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let oldKey = "\(context.coordinator.lastContentHash)-\(context.coordinator.lastLanguage)"
        let newKey = "\(content.hashValue)-\(language)"

        // Only reload HTML when content/language actually changed
        if oldKey != newKey {
            guard let html = buildHTML() else {
                webView.loadHTMLString("<p style='color:red'>Failed to load resources.</p>", baseURL: nil)
                return
            }
            context.coordinator.lastContentHash = content.hashValue
            context.coordinator.lastLanguage = language
            context.coordinator.pageReady = false
            webView.loadHTMLString(html, baseURL: nil)
        }

        // Store latest search so didFinish can retry if page wasn't ready
        context.coordinator.lastSearchQuery = searchQuery
        context.coordinator.lastOnUpdate = onSearchUpdate

        // Apply search — only when page is ready so JS functions are defined
        if context.coordinator.pageReady, let q = searchQuery, !q.isEmpty {
            webView.evaluateJavaScript("doupiSearch('\(q.escapedForJS())')") { result, _ in
                if let json = result as? String,
                   let data = json.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
                    context.coordinator.matchCount = obj["count"] ?? 0
                    context.coordinator.currentIdx = obj["current"] ?? 0
                    onSearchUpdate?(obj["count"] ?? 0, obj["current"] ?? 0)
                }
            }
        } else if context.coordinator.pageReady, searchQuery?.isEmpty != false {
            webView.evaluateJavaScript("doupiSearch('')")
            context.coordinator.matchCount = 0
            context.coordinator.currentIdx = 0
            onSearchUpdate?(0, 0)
        }

        // Handle navigation
        switch searchAction {
        case .next?:
            webView.evaluateJavaScript("doupiNavigate(1)") { result, _ in
                if let idx = result as? Int {
                    context.coordinator.currentIdx = idx
                    onSearchUpdate?(context.coordinator.matchCount, idx)
                }
            }
        case .prev?:
            webView.evaluateJavaScript("doupiNavigate(-1)") { result, _ in
                if let idx = result as? Int {
                    context.coordinator.currentIdx = idx
                    onSearchUpdate?(context.coordinator.matchCount, idx)
                }
            }
        case nil: break
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastContentHash: Int = 0
        var lastLanguage: String = ""
        var pageReady = false
        var matchCount = 0
        var currentIdx = 0
        var lastSearchQuery: String? = nil
        var lastOnUpdate: ((Int, Int) -> Void)? = nil

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) { }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageReady = true
            // Retry last search that was set before page became ready
            if let q = lastSearchQuery, !q.isEmpty {
                webView.evaluateJavaScript("doupiSearch('\(q.escapedForJS())')") { result, _ in
                    if let json = result as? String,
                       let data = json.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
                        self.matchCount = obj["count"] ?? 0
                        self.currentIdx = obj["current"] ?? 0
                        self.lastOnUpdate?(obj["count"] ?? 0, obj["current"] ?? 0)
                    }
                }
            } else if lastSearchQuery?.isEmpty != false {
                webView.evaluateJavaScript("doupiSearch('')")
                self.matchCount = 0
                self.currentIdx = 0
                self.lastOnUpdate?(0, 0)
            }
        }
    }

    // MARK: - Private helpers

    private func buildConfig() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        let pref = WKWebpagePreferences()
        pref.allowsContentJavaScript = true
        config.defaultWebpagePreferences = pref
        return config
    }

    /// Load highlight.min.js & highlight.min.css from the SPM resource bundle
    /// and assemble a self-contained HTML document with inline search JS.
    private func buildHTML() -> String? {
        guard let cssURL = Bundle.module.url(forResource: "highlight.min", withExtension: "css"),
              let jsURL  = Bundle.module.url(forResource: "highlight.min", withExtension: "js"),
              let css    = try? String(contentsOf: cssURL, encoding: .utf8),
              let js     = try? String(contentsOf: jsURL, encoding: .utf8)
        else { return nil }

        let escaped  = escapeHTML(content)
        let language = self.language.isEmpty ? "plaintext" : self.language

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light">
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
          background: transparent;
          font-family: -apple-system, "SF Mono", Menlo, Consolas, monospace;
          font-size: 14px;
          line-height: 1.6;
          padding: 16px;
          color: #1d1d1f;
        }
        pre { margin: 0; white-space: pre-wrap; word-break: break-word; }
        code { background: transparent !important; }
        \(SearchJS.styleCSS)
        \(css)
        </style>
        </head>
        <body>
        <pre><code class="language-\(language)">\(escaped)</code></pre>
        <script>\(js)</script>
        <script>
        document.addEventListener('DOMContentLoaded', function () {
          document.querySelectorAll('pre code').forEach(function (block) {
            hljs.highlightElement(block);
          });
        });
        </script>
        <script>
        \(SearchJS.functionsJS)
        </script>
        </body>
        </html>
        """
    }

    private func escapeHTML(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#x27;")
    }
}
