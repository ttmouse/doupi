import SwiftUI
import WebKit

/// A WKWebView wrapper supporting two loading modes:
/// 1. HTML string (for code previews, inline content)
/// 2. File URL (for HTML files and TSX build output)
///
/// Reports navigation errors via `onNavigationError` callback.
/// Supports text search via JS injection (same `doupiSearch`/`doupiNavigate` API as CodeView).
struct WebView: NSViewRepresentable {

    /// HTML string mode.
    var htmlString: String? = nil

    /// Optional base URL for htmlString mode (enables relative + CDN imports).
    var baseURL: URL? = nil

    /// File URL mode: loads a local file with readAccessRoot for sibling resources.
    var fileURL: URL? = nil
    var readAccessRoot: URL? = nil

    /// When non-nil, trigger JS search highlighting.
    var searchQuery: String? = nil
    /// Navigate between search matches.
    var searchAction: SearchAction? = nil

    /// Called when a navigation error occurs (for webRuntimeError detection).
    var onNavigationError: ((String) -> Void)? = nil

    /// Called when search results update: (matchCount, currentMatch).
    var onSearchUpdate: ((Int, Int) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onNavigationError: onNavigationError) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let pref = WKWebpagePreferences()
        pref.allowsContentJavaScript = true
        config.defaultWebpagePreferences = pref

        // Inject CSS: color-scheme auto-adapt + thin transparent scrollbar
        let scrollbarCSS = "*,*::before,*::after{scrollbar-width:thin;scrollbar-color:rgba(128,128,128,0.3) transparent!important}:root{color-scheme:light dark!important}"
        let cssScript = WKUserScript(
            source: """
            (function(){
              var s=document.createElement('style');
              s.textContent='\(scrollbarCSS)';
              document.head.appendChild(s);
              // Re-apply on DOM changes (SPA, dynamic content)
              var o=new MutationObserver(function(){
                document.documentElement.style.setProperty('scrollbar-color','rgba(128,128,128,0.3) transparent','important');
              });
              o.observe(document.body||document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['style','class']});
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(cssScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        context.coordinator.webView = webView
        // Find the NSScrollView and force overlay scrollers + clear background
        if let scrollView = webView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView {
            scrollView.scrollerStyle = .overlay
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            // Also hide all potential background-drawing subviews
            scrollView.subviews.forEach { sub in
                if let v = sub as? NSView, v !== scrollView.contentView {
                    v.layer?.backgroundColor = .clear
                }
            }
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Always enforce transparent overlay scrollbar on the native NSScrollView
        applyScrollbarStyle(webView)

        // Load content
        if let fileURL = fileURL {
            let key = fileURL.path
            if context.coordinator.lastLoadKey != key {
                context.coordinator.lastLoadKey = key
                context.coordinator.pageReady = false
                let root = readAccessRoot ?? fileURL.deletingLastPathComponent()
                webView.loadFileURL(fileURL, allowingReadAccessTo: root)
            }
        } else if let htmlString = htmlString {
            let key = (baseURL?.path ?? "") + htmlString
            if context.coordinator.lastLoadKey != key {
                context.coordinator.lastLoadKey = key
                context.coordinator.pageReady = false
                webView.loadHTMLString(htmlString, baseURL: baseURL)
            }
        }

        // Store search query in coordinator — didFinish retries if page not ready
        context.coordinator.pendingSearchQuery = searchQuery
        context.coordinator.pendingOnUpdate = onSearchUpdate
        context.coordinator.applySearchIfReady()

        // Handle navigation
        let onUpdate = onSearchUpdate
        switch searchAction {
        case .next?:
            webView.evaluateJavaScript("doupiNavigate(1)") { result, _ in
                if let idx = result as? Int {
                    context.coordinator.currentIdx = idx
                    onUpdate?(context.coordinator.matchCount, idx)
                }
            }
        case .prev?:
            webView.evaluateJavaScript("doupiNavigate(-1)") { result, _ in
                if let idx = result as? Int {
                    context.coordinator.currentIdx = idx
                    onUpdate?(context.coordinator.matchCount, idx)
                }
            }
        case nil: break
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadKey: String = ""
        var pageReady = false
        var matchCount = 0
        var currentIdx = 0
        var pendingSearchQuery: String? = nil
        var pendingOnUpdate: ((Int, Int) -> Void)? = nil
        weak var webView: WKWebView?
        let onNavigationError: ((String) -> Void)?

        init(onNavigationError: ((String) -> Void)?) {
            self.onNavigationError = onNavigationError
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onNavigationError?(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onNavigationError?(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(SearchJS.injectionScript)
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
                        self.matchCount = obj["count"] ?? 0
                        self.currentIdx = obj["current"] ?? 0
                        onUpdate?(obj["count"] ?? 0, obj["current"] ?? 0)
                    }
                }
            } else if pendingSearchQuery?.isEmpty != false {
                wv.evaluateJavaScript("doupiSearch('')")
                self.matchCount = 0
                self.currentIdx = 0
                onUpdate?(0, 0)
            }
        }
    }

    /// Force transparent overlay scrollbar on the WKWebView's NSScrollView.
    fileprivate func applyScrollbarStyle(_ webView: WKWebView) {
        guard let scrollView = webView.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView else { return }
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
    }
}
