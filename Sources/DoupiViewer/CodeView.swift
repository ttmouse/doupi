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
/// JS-based highlighting.
struct CodeView: NSViewRepresentable {

    let content: String
    let language: String

    var searchQuery: String? = nil
    var searchAction: SearchAction? = nil
    var onSearchUpdate: ((Int, Int) -> Void)? = nil

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let pref = WKWebpagePreferences()
        pref.allowsContentJavaScript = true
        config.defaultWebpagePreferences = pref

        // Inject search functions via WKUserScript (available before the page loads)
        let searchScript = WKUserScript(
            source: SearchJS.functionsJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(searchScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let oldKey = "\(context.coordinator.lastContentHash)-\(context.coordinator.lastLanguage)"
        let newKey = "\(content.hashValue)-\(language)"

        if oldKey != newKey {
            guard let html = buildHTML() else {
                webView.loadHTMLString("<p style='color:red'>Failed to load resources.</p>", baseURL: nil)
                return
            }
            context.coordinator.lastContentHash = content.hashValue
            context.coordinator.lastLanguage = language
            context.coordinator.pageReady = false
            context.coordinator.pendingQuery = nil
            webView.loadHTMLString(html, baseURL: nil)
        }

        // Store pending query so didFinish can retry
        context.coordinator.pendingQuery = searchQuery
        context.coordinator.pendingOnUpdate = onSearchUpdate

        // Execute if page is ready
        if context.coordinator.pageReady {
            applySearch(webView: webView, coordinator: context.coordinator)
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

    /// Execute pending search on a ready page.
    private func applySearch(webView: WKWebView, coordinator: Coordinator) {
        let onUpdate = coordinator.pendingOnUpdate
        if let q = coordinator.pendingQuery, !q.isEmpty {
            webView.evaluateJavaScript("doupiSearch('\(q.escapedForJS())')") { result, _ in
                if let json = result as? String,
                   let data = json.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
                    coordinator.matchCount = obj["count"] ?? 0
                    coordinator.currentIdx = obj["current"] ?? 0
                    onUpdate?(obj["count"] ?? 0, obj["current"] ?? 0)
                }
            }
        } else if coordinator.pendingQuery?.isEmpty != false {
            webView.evaluateJavaScript("doupiSearch('')")
            coordinator.matchCount = 0
            coordinator.currentIdx = 0
            onUpdate?(0, 0)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastContentHash: Int = 0
        var lastLanguage: String = ""
        var pageReady = false
        var matchCount = 0
        var currentIdx = 0
        var pendingQuery: String? = nil
        var pendingOnUpdate: ((Int, Int) -> Void)? = nil

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) { }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageReady = true
            // Search functions were injected via WKUserScript — always available
            if let q = pendingQuery, !q.isEmpty {
                webView.evaluateJavaScript("doupiSearch('\(q.escapedForJS())')") { result, _ in
                    if let json = result as? String,
                       let data = json.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
                        self.matchCount = obj["count"] ?? 0
                        self.currentIdx = obj["current"] ?? 0
                        self.pendingOnUpdate?(obj["count"] ?? 0, obj["current"] ?? 0)
                    }
                }
            } else if pendingQuery?.isEmpty != false {
                webView.evaluateJavaScript("doupiSearch('')")
                self.matchCount = 0
                self.currentIdx = 0
                self.pendingOnUpdate?(0, 0)
            }
        }
    }

    // MARK: - HTML builder

    private func buildHTML() -> String? {
        guard let cssURL = Bundle.module.url(forResource: "highlight.min", withExtension: "css"),
              let jsURL  = Bundle.module.url(forResource: "highlight.min", withExtension: "js"),
              let css    = try? String(contentsOf: cssURL, encoding: .utf8),
              let js     = try? String(contentsOf: jsURL, encoding: .utf8)
        else { return nil }

        let escaped  = escapeHTML(content)
        let language = self.language.isEmpty ? "plaintext" : self.language

        // NOTE: SearchJS.functionsJS is NOT embedded inline here.
        // It's injected via WKUserScript in makeNSView so it's available
        // before the page even loads, and survives page navigations.
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
