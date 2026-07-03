import SwiftUI
import WebKit

/// A minimal WKWebView wrapper for rendering HTML content.
/// Used by DocumentView when the file is a .html / .htm file.
struct WebView: NSViewRepresentable {

    let htmlString: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Allow local file access so inline scripts & styles work.
        let pref = WKWebpagePreferences()
        pref.allowsContentJavaScript = true
        config.defaultWebpagePreferences = pref

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")  // transparent background
        webView.isHidden = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(htmlString, baseURL: nil)
    }
}
