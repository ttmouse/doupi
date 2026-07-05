import SwiftUI
import WebKit

/// A WKWebView wrapper supporting two loading modes:
/// 1. HTML string (for code previews, inline content)
/// 2. File URL (for HTML files and TSX build output — enables CSS/image loading)
///
/// Reports navigation errors via `onNavigationError` callback.
struct WebView: NSViewRepresentable {

    /// HTML string mode.
    var htmlString: String? = nil

    /// Optional base URL for htmlString mode (enables relative + CDN imports).
    var baseURL: URL? = nil

    /// File URL mode: loads a local file with readAccessRoot for sibling resources.
    var fileURL: URL? = nil
    var readAccessRoot: URL? = nil

    /// Called when a navigation error occurs (for webRuntimeError detection).
    var onNavigationError: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onNavigationError: onNavigationError) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let pref = WKWebpagePreferences()
        pref.allowsContentJavaScript = true
        config.defaultWebpagePreferences = pref

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if let fileURL = fileURL {
            // File URL mode
            let key = fileURL.path
            guard context.coordinator.lastLoadKey != key else { return }
            context.coordinator.lastLoadKey = key
            let root = readAccessRoot ?? fileURL.deletingLastPathComponent()
            webView.loadFileURL(fileURL, allowingReadAccessTo: root)
        } else if let htmlString = htmlString {
            // HTML string mode
            let key = (baseURL?.path ?? "") + htmlString
            guard context.coordinator.lastLoadKey != key else { return }
            context.coordinator.lastLoadKey = key
            webView.loadHTMLString(htmlString, baseURL: baseURL)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadKey: String = ""
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
    }
}
