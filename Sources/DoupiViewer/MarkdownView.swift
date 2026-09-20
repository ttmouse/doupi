import SwiftUI
import WebKit

/// Renders markdown files as formatted HTML using an inline marked.js parser.
///
/// 页面长驻：marked（有图时再加 mermaid）只加载一次，之后换文件只把解析结果推进已加载
/// 好的页面里。整页重载一次要 100–200 ms（光 mermaid 就 3.4 MB，没有图的文档也跟着扛），
/// 推内容约 0 ms——切换文件时的空白一拍就是这么来的。
struct MarkdownView: NSViewRepresentable {

    let url: URL
    var reloadToken: Int = 0
    var searchQuery: String? = nil
    var searchCommand: SearchCommand? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(searchCommand: searchCommand)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let pref = WKWebpagePreferences()
        pref.allowsContentJavaScript = true
        config.defaultWebpagePreferences = pref
        config.userContentController.add(context.coordinator.page, name: WebContentScript.scrollHandlerName)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.latestQuery = searchQuery
        loadOrPush(webView, context: context)
        applySearchIfReady(webView, context: context)
        runPendingCommand(webView, context: context)
    }

    // MARK: - 换文件

    private func loadOrPush(_ webView: WKWebView, context: Context) {
        let key = url.path
        let coordinator = context.coordinator
        guard key != coordinator.page.key || coordinator.loadedKind == nil || coordinator.reloadToken != reloadToken else { return }
        coordinator.reloadToken = reloadToken

        // A deleted file must not leave the previous document frozen on screen;
        // the next watcher event will push its replacement when it reappears.
        let markdown = (try? String(contentsOf: url, encoding: .utf8)) ?? "文件已删除或暂时无法读取。"
        guard let json = Self.jsonString(markdown) else { return }

        let kind = MarkdownShellKind.needed(for: markdown)
        let restoreY = ScrollMemory.shared.offset(for: key)
        coordinator.page.begin(key)

        guard coordinator.loadedKind == kind else {
            // 换壳（或第一次进这个渲染器）：整页加载一次，之后这份壳一直用下去
            coordinator.loadedKind = kind
            coordinator.pageReady = false
            webView.loadHTMLString(
                Self.shellHTML(kind: kind, initialJSON: json, initialY: restoreY),
                baseURL: nil
            )
            return
        }

        // 同一种壳：只推内容。页面、渲染器、主题都不动。
        webView.evaluateJavaScript("window.__doupiPush(\(json), \(WebContentScript.number(restoreY))); 1") { _, _ in
            // innerHTML 换掉之后旧的 <mark> 全没了，把当前搜索重新盖上去
            self.applySearchIfReady(webView, context: context)
        }
    }

    private static func jsonString(_ markdown: String) -> String? {
        // 编码成 JSON 字面量：JSONEncoder 会正确转义 `\`、`"`、换行、制表符，
        // 以及关键的 `/` → `\/`，防止 `</script>` 把脚本标签提前关掉。
        guard let data = try? JSONEncoder().encode(markdown) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 搜索

    private func applySearchIfReady(_ webView: WKWebView, context: Context) {
        guard context.coordinator.pageReady else { return }
        if let q = searchQuery, !q.isEmpty {
            webView.evaluateJavaScript("doupiSearch('\(q.escapedForJS())')")
        } else if searchQuery?.isEmpty != false {
            webView.evaluateJavaScript("doupiSearch('')")
        }
    }

    /// 长驻页面上的搜索指令只能执行一次，靠编号区分新旧。
    private func runPendingCommand(_ webView: WKWebView, context: Context) {
        guard let action = context.coordinator.take(searchCommand) else { return }
        guard context.coordinator.pageReady else {
            // 页面还在加载，指令先存着，didFinish 之后补上
            context.coordinator.pendingAction = action
            return
        }
        Self.navigate(webView, action: action)
    }

    static func navigate(_ webView: WKWebView, action: SearchAction) {
        webView.evaluateJavaScript("doupiNavigate(\(action == .next ? 1 : -1))")
    }

    // MARK: - 页面壳

    /// 长驻页面的 HTML：渲染器 + 样式 + 推内容 / 上报滚动位置的接口，不含具体文档内容。
    /// - Parameters:
    ///   - initialJSON: 首次加载直接放进页面的文档，省掉一次往返
    ///   - initialY: 首次加载要恢复的滚动位置
    static func shellHTML(kind: MarkdownShellKind, initialJSON: String, initialY: Double) -> String {
        let markedJS = loadMarkedJS()
        let mermaidParts = kind == .mermaid
            ? """
              <script>\(loadMermaidJS())</script>
              <script>
              mermaid.initialize({
                  startOnLoad: false,
                  securityLevel: 'strict',
                  theme: 'base',
                  fontFamily: '-apple-system,BlinkMacSystemFont,"Segoe UI","Noto Sans",Helvetica,Arial,sans-serif',
                  themeVariables: {
                      primaryColor: '#e9f3e0',
                      primaryBorderColor: '#7BC043',
                      primaryTextColor: '#1d1d1f',
                      lineColor: '#8a867f',
                      secondaryColor: '#f3f2ee',
                      tertiaryColor: '#faf9f6',
                      fontSize: '14px'
                  }
              });
              </script>
              """
            : ""

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
        .markdown-body .mermaid{text-align:center;margin:16px 0;overflow-x:auto}
        .markdown-body .mermaid svg{max-width:100%;height:auto}
        .markdown-body .mermaid-error{background:rgba(0,0,0,0.05);border:1px solid #e5b8b4;color:#9a3b34;padding:12px 16px;border-radius:6px;font-size:13px;margin:16px 0}
        </style></head><body><div class="markdown-body" id="content"></div>
        <script>\(markedJS)</script>
        \(mermaidParts)
        <script>
        window.__doupiPush = function (mdJSON, y) {
            window._doupiMatches = [];
            window._doupiCurrent = -1;
            document.getElementById('content').innerHTML = marked.parse(mdJSON);
            function restore() { if (y > 0) window.scrollTo(0, y); }
            var jobs = [];
            if (window.mermaid) {
                var blocks = document.querySelectorAll('pre code.language-mermaid');
                blocks.forEach(function (code, i) {
                    var pre = code.parentNode;
                    var id = 'mermaid-' + Date.now() + '-' + i;
                    jobs.push(mermaid.render(id, code.textContent).then(function (res) {
                        var holder = document.createElement('div');
                        holder.className = 'mermaid';
                        holder.innerHTML = res.svg;
                        pre.replaceWith(holder);
                    }).catch(function (e) {
                        console.error('[mermaid] render failed:', e);
                        var note = document.createElement('div');
                        note.className = 'mermaid-error';
                        note.textContent = '⚠ 图表渲染失败（Mermaid 语法错误）';
                        pre.replaceWith(note);
                    }));
                });
            }
            restore();
            // 图是异步画的，画完页面高度才定下来，位置要在那之后再钉一次
            if (jobs.length) Promise.all(jobs).then(restore);
        };
        \(WebContentScript.reportScroll)
        \(WebContentScript.pinScroll(to: initialY))
        window.__doupiPush(\(initialJSON), \(WebContentScript.number(initialY)));
        </script>
        </body></html>
        """
    }

    private static func loadMermaidJS() -> String {
        guard let url = Bundle.module.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "Resources"),
              let js = try? String(contentsOf: url, encoding: .utf8) else {
            fputs("[MarkdownView] cannot load mermaid.min.js from bundle\n", stderr)
            return ""
        }
        return js
    }

    private static func loadMarkedJS() -> String {
        guard let url = Bundle.module.url(forResource: "marked.min", withExtension: "js", subdirectory: "Resources"),
              let js = try? String(contentsOf: url, encoding: .utf8) else {
            fputs("[MarkdownView] cannot load marked.min.js from bundle\n", stderr)
            return ""
        }
        return js
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        let page = ContentPageState()
        /// 当前页面里装的是哪种壳；nil 表示这份页面还不能推内容
        var loadedKind: MarkdownShellKind?
        var reloadToken = -1
        var pageReady = false
        var latestQuery: String?
        var pendingAction: SearchAction?
        private var gate: SearchCommandGate

        init(searchCommand: SearchCommand?) {
            gate = SearchCommandGate(seen: searchCommand)
        }

        func take(_ command: SearchCommand?) -> SearchAction? {
            gate.take(command)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(MarkdownView.searchJS)
            pageReady = true
            if let q = latestQuery, !q.isEmpty {
                webView.evaluateJavaScript("doupiSearch('\(q.escapedForJS())')")
            }
            // 加载期间按下的 ⌘G 不该丢
            if let action = pendingAction {
                pendingAction = nil
                MarkdownView.navigate(webView, action: action)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            resetPageAfterFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            resetPageAfterFailure(error)
        }

        /// 整页没加载起来时把壳作废，下一次更新会重新加载，而不是往空页面里推内容。
        private func resetPageAfterFailure(_ error: Error) {
            fputs("[MarkdownView] page load failed: \(error.localizedDescription)\n", stderr)
            loadedKind = nil
            pageReady = false
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
