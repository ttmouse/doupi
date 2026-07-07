import SwiftUI
import WebKit

/// Renders markdown files as formatted HTML using an inline marked.js parser.
struct MarkdownView: NSViewRepresentable {
    let url: URL
    var searchQuery: String? = nil
    var searchAction: SearchAction? = nil

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
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let key = url.path
        guard context.coordinator.lastLoadKey != key else {
            applySearchIfReady(webView, context: context)
            return
        }
        context.coordinator.lastLoadKey = key
        context.coordinator.pageReady = false

        guard let md = try? String(contentsOf: url, encoding: .utf8) else { return }

        let escaped = md
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")

        let html = buildHTML(markdown: escaped)
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func applySearchIfReady(_ webView: WKWebView, context: Context) {
        guard context.coordinator.pageReady else { return }
        if let q = searchQuery, !q.isEmpty {
            webView.evaluateJavaScript("doupiSearch('\(q.escapedForJS())')")
        } else if searchQuery?.isEmpty != false {
            webView.evaluateJavaScript("doupiSearch('')")
        }

        switch searchAction {
        case .next?: webView.evaluateJavaScript("doupiNavigate(1)")
        case .prev?: webView.evaluateJavaScript("doupiNavigate(-1)")
        case nil: break
        }
    }

    // MARK: - HTML builder

    private func buildHTML(markdown: String) -> String {
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
        <script>document.getElementById('content').innerHTML=marked.parse(`\(markdown)`);</script>
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
        let searchAction: SearchAction?

        init(searchAction: SearchAction?) {
            self.searchAction = searchAction
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(MarkdownView.searchJS)
            pageReady = true
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

    // MARK: - Search JS

    private static let searchJS = """
    (function(){if(window._doupiInjected)return;window._doupiInjected=true;
    var s=document.createElement('style');
    s.textContent='mark.doupi-search{background:rgba(93,154,50,0.35);color:inherit;border-radius:2px}mark.doupi-current{background:rgba(93,154,50,0.65);outline:1px solid rgba(93,154,50,0.8);border-radius:2px}';
    document.head.appendChild(s);
    window._doupiMatches=[];window._doupiCurrent=-1;
    window.doupiSearch=function(q){
    document.querySelectorAll('mark.doupi-search,mark.doupi-current').forEach(function(m){var p=m.parentNode;while(m.firstChild)p.insertBefore(m.firstChild,m);p.removeChild(m)});
    window._doupiMatches=[];window._doupiCurrent=-1;
    if(!q)return JSON.stringify({count:0,current:-1});
    var w=document.createTreeWalker(document.body,4,null),ql=q.toLowerCase(),n,r;
    while(n=w.nextNode()){var p=n.parentNode;if(p&&(p.nodeName==='MARK'||p.nodeName==='SCRIPT'||p.nodeName==='STYLE'))continue;
    var t=n.textContent,i=t.toLowerCase().indexOf(ql);
    if(i>=0){r=document.createRange();r.setStart(n,i);r.setEnd(n,i+q.length);
    try{var mk=document.createElement('mark');mk.className='doupi-search';r.surroundContents(mk);window._doupiMatches.push(mk);w.currentNode=mk}catch(e){}}}
    return JSON.stringify({count:window._doupiMatches.length,current:window._doupiCurrent});
    };
    window.doupiNavigate=function(d){
    if(window._doupiMatches.length===0)return -1;
    if(window._doupiCurrent>=0&&window._doupiCurrent<window._doupiMatches.length)window._doupiMatches[window._doupiCurrent].className='doupi-search';
    window._doupiCurrent+=d;
    if(window._doupiCurrent>=window._doupiMatches.length)window._doupiCurrent=0;
    if(window._doupiCurrent<0)window._doupiCurrent=window._doupiMatches.length-1;
    window._doupiMatches[window._doupiCurrent].className='doupi-current';
    window._doupiMatches[window._doupiCurrent].scrollIntoView({behavior:'smooth',block:'center'});
    return window._doupiCurrent;
    };
    })();
    """
}
