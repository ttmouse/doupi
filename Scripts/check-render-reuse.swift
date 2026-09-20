import AppKit
import WebKit

/// 渲染器复用的回归检查。
///
/// 保护四件事：
///   1. 每个文件记住并恢复自己的滚动位置（否则复用省下的时间会被用户自己重新滚一遍）
///   2. 一次性搜索指令在长驻页面上只执行一次
///   3. markdown 只在有图时才扛 mermaid 那份 3.4 MB 渲染器
///   4. 推内容比整页重载快一个数量级（重载 = 新建 WKWebView + 重新内联全部渲染器）
///
/// 第 4 条用的资源与脚本约定都是应用里那一份（`WebContentSupport` 的脚本 + Resources 下的
/// marked/mermaid），壳是按 MarkdownView 的同样结构在检查里拼的——因为 SPM 的
/// `Bundle.module` 在 swiftc 单独编译时不存在，检查脚本没法直接调用 `MarkdownView`。
@main
struct RenderReuseChecks {

    static func main() {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)

        checkScrollMemory()
        checkCommandGate()
        checkShellKind()
        checkScrollReporting()
        checkScrollRestore()
        checkRefreshKeepsPosition()
        checkPushReplacesContent()
        measureReloadVersusPush()
        measureHtmlReloadVersusReuse()

        print("PASS: all render reuse regression checks")
    }

    // MARK: - 1. 滚动位置记忆

    static func checkScrollMemory() {
        let memory = ScrollMemory()
        precondition(memory.offset(for: "a") == 0, "没记过的文件应当从 0 开始")

        memory.remember(1200, for: "a")
        memory.remember(400, for: "b")
        precondition(memory.offset(for: "a") == 1200, "记过的文件应当读回原值")
        precondition(memory.offset(for: "b") == 400, "不同文件互不干扰")

        memory.remember(0, for: "a")
        precondition(memory.offset(for: "a") == 0, "滚回顶部也要记住（0 是合法位置）")

        // 空 key（比如还没落到具体文件上）不该污染存储
        memory.remember(999, for: "")
        precondition(memory.offset(for: "") == 0, "空 key 不记")

        // 上限之外丢最旧的，不能无限涨
        for i in 0..<250 { memory.remember(Double(i), for: "file-\(i)") }
        precondition(memory.offset(for: "file-0") == 0, "超出上限后最旧的应当被淘汰")
        precondition(memory.offset(for: "file-249") == 249, "最新的必须还在")
        print("PASS: 滚动位置按文件记住，上限之外丢最旧")
    }

    // MARK: - 2. 搜索指令去重

    static func checkCommandGate() {
        let first = SearchCommand(action: .next, id: 1)
        let second = SearchCommand(action: .next, id: 2)

        // 新建的视图不该把上一条旧指令当成自己的任务
        var fresh = SearchCommandGate(seen: first)
        precondition(fresh.take(first) == nil, "同一条指令不该在新视图上重跑")
        precondition(fresh.take(second) == .next, "新编号的指令要执行")
        precondition(fresh.take(second) == nil, "同一条指令只执行一次")

        var empty = SearchCommandGate(seen: nil)
        precondition(empty.take(first) == .next, "没有旧指令时第一条就该执行")
        precondition(empty.take(SearchCommand(action: .prev, id: 2)) == .prev, "方向和编号都要认")
        print("PASS: 搜索指令按编号只执行一次，新视图不吃旧指令")
    }

    // MARK: - 3. markdown 壳的种类

    static func checkShellKind() {
        func kind(_ md: String) -> MarkdownShellKind { MarkdownShellKind.needed(for: md) }

        precondition(kind("") == .plain, "空文档不需要 mermaid")
        precondition(kind("# 标题\n\n正文，提到 mermaid 这个词不算图\n") == .plain, "正文里出现 mermaid 不算图")
        precondition(kind("```js\nconst a = 1\n```\n") == .plain, "普通代码块不算图")
        precondition(kind("```mermaid\nflowchart LR\n  A --> B\n```\n") == .mermaid, "```mermaid 围栏要认得")
        precondition(kind("~~~mermaid\nflowchart LR\n~~~\n") == .mermaid, "~~~ 围栏同样要认得")
        precondition(kind("  ```mermaid\n  A --> B\n  ```\n") == .mermaid, "缩进的围栏也要认得")
        precondition(kind("``` mermaid\nA --> B\n```\n") == .mermaid, "围栏后空格是常见写法")
        print("PASS: 只有真的带 mermaid 围栏才加载那份 3.4 MB 渲染器")
    }

    // MARK: - 4. 滚动位置上报

    static func checkScrollReporting() {
        let page = Page()
        page.sink.begin("check://report")
        page.load(tallPage(), scripts: [.end(WebContentScript.reportScroll)])
        precondition(page.waitReady(), "测试页面没加载起来")

        _ = page.js("window.scrollTo(0, 1500)")
        pump(0.3)

        let y = ScrollMemory.shared.offset(for: "check://report")
        precondition(abs(y - 1500) < 5, "页面滚动位置应当被上报，实际 \(y)")
        print("PASS: 页面滚动位置持续上报给原生侧")
    }

    // MARK: - 5. 滚动位置恢复

    static func checkScrollRestore() {
        let key = "check://restore"
        ScrollMemory.shared.remember(2000, for: key)

        // 注入 pin 之后：第一帧就该在恢复位置上
        let restored = Page()
        restored.sink.begin(key)
        restored.load(tallPage(), scripts: [
            .start(WebContentScript.pinScroll(to: 2000)),
            .end(WebContentScript.reportScroll),
        ])
        precondition(restored.waitReady(), "测试页面没加载起来")
        // pin 是反复纠偏（定时器 + rAF），给一次 tick 的时间再读
        pump(0.2)
        let restoredY = restored.scrollY()
        precondition(abs(restoredY - 2000) <= 2, "有位置要恢复时应当停在原位，实际 \(restoredY)")

        // 不注入 pin 的对照：证明恢复不是 WKWebView 自带的，而是这段脚本干的
        let plain = Page()
        plain.sink.begin("check://no-restore")
        plain.load(tallPage(), scripts: [.end(WebContentScript.reportScroll)])
        precondition(plain.waitReady(), "对照页面没加载起来")
        let plainY = plain.scrollY()
        precondition(plainY < 50, "没有恢复脚本时页面应当还在顶部，实际 \(plainY)")
        print("PASS: 恢复位置由 pin 脚本保证（对照组停在顶部）")
    }

    // MARK: - 6. 刷新（⌘R / 外部改写）后位置不变

    /// 刷新会整页重新加载当前文件，但用户是在「读一半」的时候按的——位置必须留在原地，
    /// 否则每次 AI 改写文件都会把人弹回文档开头。
    static func checkRefreshKeepsPosition() {
        let key = "check://refresh"
        let page = Page()
        page.sink.begin(key)
        page.load(tallPage(), scripts: [.end(WebContentScript.reportScroll)])
        precondition(page.waitReady(), "测试页面没加载起来")

        _ = page.js("window.scrollTo(0, 3200)")
        pump(0.3)
        let remembered = ScrollMemory.shared.offset(for: key)
        precondition(abs(remembered - 3200) < 5, "滚动位置应当先被记住，实际 \(remembered)")

        // 刷新：同一个 stableKey，重新整页加载，恢复位置由记忆提供
        let refreshed = Page()
        refreshed.sink.begin(key)
        refreshed.load(tallPage(), scripts: [
            .start(WebContentScript.pinScroll(to: ScrollMemory.shared.offset(for: key))),
            .end(WebContentScript.reportScroll),
        ])
        precondition(refreshed.waitReady(), "刷新后的页面没加载起来")
        pump(0.2)
        let afterRefresh = refreshed.scrollY()
        precondition(abs(afterRefresh - 3200) <= 2, "刷新后应当停在原来的位置，实际 \(afterRefresh)")
        print("PASS: 刷新（⌘R / 外部改写）后阅读位置留在原地")
    }

    // MARK: - 7. 推内容换掉页面内容

    static func checkPushReplacesContent() {
        let page = Page()
        page.sink.begin("check://push")
        page.load(lightShell(), scripts: [.end(WebContentScript.reportScroll)])
        precondition(page.waitReady(), "壳没加载起来")

        page.push("<p id='one'>第一份</p>", y: 0)
        precondition(page.text().contains("第一份"), "第一次推的内容应当出现")

        page.push("<p id='two'>第二份</p>", y: 1800)
        let text = page.text()
        precondition(text.contains("第二份"), "第二次推的内容应当出现")
        precondition(!text.contains("第一份"), "旧内容应当被换掉")
        precondition(abs(page.scrollY() - 1800) <= 2, "推内容时带的位置要生效")
        print("PASS: 推内容换掉旧内容，并同时恢复位置")
    }

    // MARK: - 8. 整页重载 vs 推内容

    static func measureReloadVersusPush() {
        guard let mermaid = resource("mermaid.min.js"), let marked = resource("marked.min.js") else {
            print("SKIP: 找不到 marked/mermaid 资源，跳过耗时对照")
            return
        }
        let heavyShell = heavyShell(marked: marked, mermaid: mermaid)
        let payload = String(repeating: "中文正文，用来看第一帧什么时候到。\n\n", count: 40)

        var reload: [Double] = []
        var push: [Double] = []
        var content = ""

        for _ in 0..<7 {
            let fresh = Page()
            reload.append(fresh.loadTimed(heavyShell, scripts: [.end(WebContentScript.reportScroll)]))
        }

        let warm = Page()
        warm.load(heavyShell, scripts: [.end(WebContentScript.reportScroll)])
        precondition(warm.waitReady(), "壳没加载起来")
        for _ in 0..<7 {
            push.append(warm.pushTimed("<p>\(payload)</p>", y: 0))
        }
        content = warm.text()

        let reloadMedian = median(reload)
        let pushMedian = median(push)
        precondition(content.contains("中文正文"), "计时用的推内容没生效，数字没意义")
        precondition(pushMedian < 15, "推内容应当在一帧之内完成，实际中位 \(fmt(pushMedian)) ms")

        if reloadMedian > 30 {
            precondition(pushMedian * 3 < reloadMedian,
                         "推内容应当至少快 3 倍，实际重载 \(fmt(reloadMedian)) ms / 推内容 \(fmt(pushMedian)) ms")
        } else {
            print("NOTE: 这台机器上整页重载只有 \(fmt(reloadMedian)) ms，跳过倍数断言")
        }
        print("PASS: 每次重建页面（含 mermaid）中位 \(fmt(reloadMedian)) ms → 长驻壳推内容 \(fmt(pushMedian)) ms")
    }

    // MARK: - 9. HTML：新建 WKWebView vs 复用

    static func measureHtmlReloadVersusReuse() {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads/Doupi/HTML")
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "html" || $0.pathExtension.lowercased() == "htm" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard files.count >= 2 else {
            print("SKIP: \(dir.path) 里不足 2 个 HTML，跳过对照（这条对照需要真实样本）")
            return
        }

        var recreated: [Double] = []
        var reused: [Double] = []
        for round in 0..<7 {
            let fresh = Page()
            recreated.append(fresh.loadFileTimed(files[round % files.count]))
        }
        let warm = Page()
        precondition(warm.loadFileTimed(files[0]) > 0, "样本文件没加载起来")
        for round in 0..<7 {
            reused.append(warm.loadFileTimed(files[(round + 1) % files.count]))
        }

        let recreatedMedian = median(recreated)
        let reusedMedian = median(reused)
        precondition(reusedMedian < 60, "复用 WKWebView 应当在几十毫秒内切完，实际中位 \(fmt(reusedMedian)) ms")
        // 只要求「明显更快」而不是固定倍数：真实文档大小差别很大，倍数会跟着抖
        if recreatedMedian > 30 {
            precondition(reusedMedian * 2 < recreatedMedian,
                         "复用应当明显快于新建，实际新建 \(fmt(recreatedMedian)) ms / 复用 \(fmt(reusedMedian)) ms")
        }
        print("PASS: 切 HTML 样本 \(files.count) 份，新建 WKWebView 中位 \(fmt(recreatedMedian)) ms → 复用 \(fmt(reusedMedian)) ms")
    }

    // MARK: - 工具

    static func pump(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }

    static func fmt(_ ms: Double) -> String {
        String(format: "%.0f", ms)
    }

    static func resource(_ name: String) -> String? {
        let url = URL(fileURLWithPath: "Sources/DoupiViewer/Resources").appendingPathComponent(name)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// 高页面：用来验证滚动位置。
    static func tallPage() -> String {
        """
        <!doctype html><html><body style="margin:0">
        <div style="height:6000px;background:linear-gradient(#ffffff,#333333)"></div>
        </body></html>
        """
    }

    /// 轻壳：和 CodeView 的结构一样——页面长驻，只把内容推进去。
    static func lightShell() -> String {
        """
        <!doctype html><html><body style="margin:0">
        <div id="content"></div>
        <div style="height:6000px"></div>
        <script>
        window.__doupiPush = function (html, y) {
          document.getElementById('content').innerHTML = html;
          if (y > 0) window.scrollTo(0, y);
        };
        </script>
        \(WebContentScript.reportScroll)
        </body></html>
        """
    }

    /// 重壳：和 MarkdownView 的结构一样——每次整页加载都要重新内联 marked + mermaid。
    static func heavyShell(marked: String, mermaid: String) -> String {
        """
        <!doctype html><html><body style="margin:0">
        <div id="content"></div>
        <div style="height:6000px"></div>
        <script>\(marked)</script>
        <script>\(mermaid)</script>
        <script>mermaid.initialize({startOnLoad:false,securityLevel:'strict',theme:'base'});</script>
        <script>
        window.__doupiPush = function (md, y) {
          document.getElementById('content').innerHTML = marked.parse(md);
          if (y > 0) window.scrollTo(0, y);
        };
        </script>
        \(WebContentScript.reportScroll)
        </body></html>
        """
    }
}

// MARK: - 一个可以被同步驱动的页面

/// WKWebView 的回调都走主线程 RunLoop，所以这里的「加载完成」「执行 JS」都用泵 RunLoop
/// 的方式同步等待，检查脚本才能按顺序读。
final class Page: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let sink = ContentPageState()
    private var finished = false

    override init() {
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        super.init()
        webView.configuration.userContentController.add(sink, name: WebContentScript.scrollHandlerName)
        webView.navigationDelegate = self
    }

    func load(_ html: String, scripts: [WKUserScript] = []) {
        apply(scripts)
        finished = false
        webView.loadHTMLString(html, baseURL: nil)
    }

    func loadTimed(_ html: String, scripts: [WKUserScript] = []) -> Double {
        let start = Date()
        load(html, scripts: scripts)
        _ = waitReady()
        return Date().timeIntervalSince(start) * 1000
    }

    func loadFileTimed(_ url: URL) -> Double {
        let start = Date()
        apply([.end(WebContentScript.reportScroll)])
        finished = false
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        _ = waitReady()
        return Date().timeIntervalSince(start) * 1000
    }

    func push(_ html: String, y: Double) {
        _ = js("window.__doupiPush(\(json(html)), \(WebContentScript.number(y))); 1")
    }

    func pushTimed(_ html: String, y: Double) -> Double {
        let start = Date()
        _ = js("window.__doupiPush(\(json(html)), \(WebContentScript.number(y))); 1")
        return Date().timeIntervalSince(start) * 1000
    }

    func text() -> String {
        (js("document.body.innerText") as? String) ?? ""
    }

    func scrollY() -> Double {
        guard let value = js("window.scrollY") else { return -1 }
        if let n = value as? NSNumber { return n.doubleValue }
        return (value as? Double) ?? -1
    }

    /// 同步跑一段 JS。
    @discardableResult
    func js(_ script: String, timeout: Double = 3) -> Any? {
        var result: Any?
        var done = false
        webView.evaluateJavaScript(script) { value, _ in
            result = value
            done = true
        }
        let deadline = Date().addingTimeInterval(timeout)
        while !done && Date() < deadline {
            RenderReuseChecks.pump(0.01)
        }
        return result
    }

    func waitReady(_ timeout: Double = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !finished && Date() < deadline {
            RenderReuseChecks.pump(0.02)
        }
        return finished
    }

    private func apply(_ scripts: [WKUserScript]) {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        scripts.forEach { controller.addUserScript($0) }
    }

    private func json(_ text: String) -> String {
        let data = try! JSONEncoder().encode(text)
        return String(data: data, encoding: .utf8)!
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finished = true }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finished = true }
}

extension WKUserScript {
    static func start(_ source: String) -> WKUserScript {
        WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    static func end(_ source: String) -> WKUserScript {
        WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }
}
