import SwiftUI
import WebKit

/// Renders source code with syntax highlighting via highlight.js v11
/// inside a transparent-background WKWebView. Supports text search with
/// JS-based highlighting.
///
/// 页面长驻：highlight.js 只在第一次加载，之后换文件只把代码文本推进去。整页重载虽然
/// 只有 120 KB 的运行时，但新建 WKWebView 本身要 ~90 ms；推内容 ~0 ms。
struct CodeView: NSViewRepresentable {

    let content: String
    let language: String

    /// 这份内容属于哪个文件——滚动位置要按文件记，不然两个内容相同的文件会互相串位。
    var contentKey: String = ""
    /// Incremented by the file watcher or ⌘R to force a same-content refresh.
    var reloadToken: Int = 0

    /// When non-nil, the JS search highlighter is triggered.
    var searchQuery: String? = nil

    /// 一次性搜索指令（带编号，长驻页面上只执行一次）。
    var searchCommand: SearchCommand? = nil

    /// Called when search results update: (matchCount, currentMatch).
    var onSearchUpdate: ((Int, Int) -> Void)? = nil

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(searchCommand: searchCommand)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = buildConfig()
        config.userContentController.add(context.coordinator.page, name: WebContentScript.scrollHandlerName)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.latestQuery = searchQuery
        context.coordinator.onSearchUpdate = onSearchUpdate
        loadOrPush(webView, context: context)
        applySearchIfReady(webView, context: context)
        runPendingCommand(webView, context: context)
    }

    // MARK: - 换文件

    private func loadOrPush(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        let hashed = "\(contentKey)|\(reloadToken)|\(content.hashValue)-\(language)"
        guard hashed != coordinator.contentKey || !coordinator.shellLoaded else { return }

        let languageClass = language.isEmpty ? "plaintext" : language
        guard let json = Self.jsonString(escapeHTML(content)) else { return }
        let key = contentKey.isEmpty ? coordinator.page.key : contentKey
        let push = Coordinator.Push(
            json: json,
            languageJSON: Self.jsonString(languageClass) ?? "\"plaintext\"",
            y: ScrollMemory.shared.offset(for: key)
        )
        coordinator.contentKey = hashed
        coordinator.page.begin(key)

        if coordinator.shellLoaded, coordinator.pageReady {
            coordinator.apply(webView, push)
        } else {
            // 第一次（或者上一次整页加载没起来）：整页加载一次，之后这份壳一直用下去
            coordinator.shellLoaded = true
            coordinator.pageReady = false
            coordinator.pendingPush = push
            webView.loadHTMLString(Self.shellHTML(), baseURL: nil)
        }
    }

    private static func jsonString(_ text: String) -> String? {
        guard let data = try? JSONEncoder().encode(text) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 搜索

    private func applySearchIfReady(_ webView: WKWebView, context: Context) {
        let onUpdate = onSearchUpdate
        let coordinator = context.coordinator
        guard coordinator.pageReady else { return }

        if let q = searchQuery, !q.isEmpty {
            webView.evaluateJavaScript("doupiSearch('\(q.escapedForJS())')") { result, _ in
                guard let counts = Self.matchCounts(from: result) else { return }
                coordinator.matchCount = counts.0
                coordinator.currentIdx = counts.1
                onUpdate?(counts.0, counts.1)
            }
        } else if searchQuery?.isEmpty != false {
            webView.evaluateJavaScript("doupiSearch('')")
            coordinator.matchCount = 0
            coordinator.currentIdx = 0
            onUpdate?(0, 0)
        }
    }

    /// 长驻页面上的搜索指令只能执行一次，靠编号区分新旧。
    private func runPendingCommand(_ webView: WKWebView, context: Context) {
        guard let action = context.coordinator.take(searchCommand) else { return }
        guard context.coordinator.pageReady else {
            context.coordinator.pendingAction = action
            return
        }
        Self.navigate(webView, action: action, coordinator: context.coordinator)
    }

    static func navigate(_ webView: WKWebView, action: SearchAction, coordinator: Coordinator) {
        let onUpdate = coordinator.onSearchUpdate
        webView.evaluateJavaScript("doupiNavigate(\(action == .next ? 1 : -1))") { result, _ in
            if let idx = result as? Int {
                coordinator.currentIdx = idx
                onUpdate?(coordinator.matchCount, idx)
            }
        }
    }

    private static func matchCounts(from result: Any?) -> (Int, Int)? {
        guard let json = result as? String,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Int]
        else { return nil }
        return (obj["count"] ?? 0, obj["current"] ?? 0)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        struct Push {
            let json: String
            let languageJSON: String
            let y: Double
        }

        /// 长驻页面的身份与滚动记忆
        let page = ContentPageState()
        /// 页面里已经装好 highlight.js 了吗
        var shellLoaded = false
        var pageReady = false
        /// 当前页面里是哪份内容
        var contentKey: String = ""
        var latestQuery: String?
        var pendingAction: SearchAction?
        var pendingPush: Push?
        var matchCount = 0
        var currentIdx = 0
        var onSearchUpdate: ((Int, Int) -> Void)?
        private var gate: SearchCommandGate

        init(searchCommand: SearchCommand?) {
            gate = SearchCommandGate(seen: searchCommand)
        }

        func take(_ command: SearchCommand?) -> SearchAction? {
            gate.take(command)
        }

        /// 把内容推进已经加载好的页面里
        func apply(_ webView: WKWebView, _ push: Push) {
            webView.evaluateJavaScript(
                "window.__doupiPush(\(push.json), \(push.languageJSON), \(WebContentScript.number(push.y))); 1"
            )
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageReady = true
            if let push = pendingPush {
                pendingPush = nil
                apply(webView, push)
            }
            if let q = latestQuery, !q.isEmpty {
                webView.evaluateJavaScript("doupiSearch('\(q.escapedForJS())')")
            }
            // 加载期间按下的 ⌘G 不该丢
            if let action = pendingAction {
                pendingAction = nil
                CodeView.navigate(webView, action: action, coordinator: self)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            markPageUnusable(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            markPageUnusable(error)
        }

        /// 整页没加载起来时把壳作废，下一次更新会重新加载，而不是往空页面里推内容。
        private func markPageUnusable(_ error: Error) {
            fputs("[CodeView] page load failed: \(error.localizedDescription)\n", stderr)
            shellLoaded = false
            pageReady = false
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

    /// 长驻页面的 HTML：highlight.js + 样式 + 推内容的接口，不含具体代码。
    static func shellHTML() -> String {
        guard let cssURL = Bundle.module.url(forResource: "highlight.min", withExtension: "css", subdirectory: "Resources"),
              let jsURL  = Bundle.module.url(forResource: "highlight.min", withExtension: "js", subdirectory: "Resources"),
              let css    = try? String(contentsOf: cssURL, encoding: .utf8),
              let js     = try? String(contentsOf: jsURL, encoding: .utf8)
        else { return "<p style='color:red'>Failed to load resources.</p>" }

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
        <pre><code id="doupi-code" class="language-plaintext"></code></pre>
        <script>\(js)</script>
        <script>
        window.__doupiPush = function (codeHTML, language, y) {
          window._doupiMatches = [];
          window._doupiCurrent = -1;
          var code = document.getElementById('doupi-code');
          code.className = 'language-' + language;
          code.innerHTML = codeHTML;
          // highlight.js v11 用 data-highlighted 标记“已经高亮过”，换内容前要清掉
          code.removeAttribute('data-highlighted');
          if (window.hljs) hljs.highlightElement(code);
          if (y > 0) window.scrollTo(0, y);
        };
        \(WebContentScript.reportScroll)
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
}
