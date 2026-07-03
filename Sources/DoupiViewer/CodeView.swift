import SwiftUI
import WebKit

/// Renders source code with syntax highlighting via highlight.js v11
/// inside a transparent-background WKWebView.
struct CodeView: NSViewRepresentable {

    let content: String
    let language: String

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> WKWebView {
        let config = buildConfig()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let html = buildHTML() else {
            webView.loadHTMLString("<p style='color:red;font-family:sans-serif'>Failed to load highlighting resources.</p>", baseURL: nil)
            return
        }
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator (handles navigation events)

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            // Silently ignore — the page still renders partially.
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
