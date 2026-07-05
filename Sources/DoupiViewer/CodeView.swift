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

    /// When non-nil, the JS search highlighter is triggered.
    var searchQuery: String? = nil

    /// Called by the parent to navigate between matches.
    var searchAction: SearchAction? = nil

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> WKWebView {
        let config = buildConfig()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
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

        // Apply search if needed
        if context.coordinator.pageReady, let q = searchQuery, !q.isEmpty {
            webView.evaluateJavaScript("doupiSearch('\(escapeJS(q))')") { result, _ in
                if let json = result as? String,
                   let data = json.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
                    context.coordinator.matchCount = obj["count"] ?? 0
                    context.coordinator.currentIdx = obj["current"] ?? 0
                }
            }
        } else if context.coordinator.pageReady, searchQuery?.isEmpty != false {
            // Clear highlights
            webView.evaluateJavaScript("doupiSearch('')")
            context.coordinator.matchCount = 0
            context.coordinator.currentIdx = 0
        }

        // Handle navigation
        switch searchAction {
        case .next?:
            webView.evaluateJavaScript("doupiNavigate(1)") { result, _ in
                if let idx = result as? Int { context.coordinator.currentIdx = idx }
            }
        case .prev?:
            webView.evaluateJavaScript("doupiNavigate(-1)") { result, _ in
                if let idx = result as? Int { context.coordinator.currentIdx = idx }
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

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) { }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageReady = true
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
    /// and assemble a self-contained HTML document.
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
          font-size: 13px;
          line-height: 1.5;
          padding: 16px;
          color: #1d1d1f;
        }
        pre { margin: 0; white-space: pre-wrap; word-break: break-word; }
        code { background: transparent !important; }
        mark.doupi-search {
          background: rgba(93,154,50,0.35);
          color: inherit;
          border-radius: 2px;
        }
        mark.doupi-current {
          background: rgba(93,154,50,0.65);
          outline: 1px solid rgba(93,154,50,0.8);
          border-radius: 2px;
        }
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
        var _doupiMatches = [];
        var _doupiCurrent = -1;

        function doupiSearch(query) {
          // Clear old highlights
          document.querySelectorAll('mark.doupi-search,mark.doupi-current').forEach(function(m) {
            var parent = m.parentNode;
            while (m.firstChild) parent.insertBefore(m.firstChild, m);
            parent.removeChild(m);
          });
          _doupiMatches = [];
          _doupiCurrent = -1;

          if (!query) return JSON.stringify({count:0,current:-1});

          var walker = document.createTreeWalker(document.body, 4/*SHOW_TEXT*/, null);
          var qLower = query.toLowerCase();
          var node;
          var ranges = [];

          while (node = walker.nextNode()) {
            // Skip nodes inside <mark>, <script>, <style>
            var p = node.parentNode;
            if (p && (p.nodeName === 'MARK' || p.nodeName === 'SCRIPT' || p.nodeName === 'STYLE')) continue;

            var text = node.textContent;
            var idx = text.toLowerCase().indexOf(qLower);
            if (idx >= 0) {
              var range = document.createRange();
              range.setStart(node, idx);
              range.setEnd(node, idx + query.length);
              try {
                var mark = document.createElement('mark');
                mark.className = 'doupi-search';
                range.surroundContents(mark);
                _doupiMatches.push(mark);
                walker.currentNode = mark;
              } catch(e) {}
            }
          }
          return JSON.stringify({count:_doupiMatches.length,current:_doupiCurrent});
        }

        function doupiNavigate(dir) {
          if (_doupiMatches.length === 0) return -1;
          // Remove current highlight
          if (_doupiCurrent >= 0 && _doupiCurrent < _doupiMatches.length) {
            _doupiMatches[_doupiCurrent].className = 'doupi-search';
          }
          // Advance
          _doupiCurrent += dir;
          if (_doupiCurrent >= _doupiMatches.length) _doupiCurrent = 0;
          if (_doupiCurrent < 0) _doupiCurrent = _doupiMatches.length - 1;
          // Highlight current
          _doupiMatches[_doupiCurrent].className = 'doupi-current';
          _doupiMatches[_doupiCurrent].scrollIntoView({behavior:'smooth',block:'center'});
          return _doupiCurrent;
        }
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

    private func escapeJS(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
