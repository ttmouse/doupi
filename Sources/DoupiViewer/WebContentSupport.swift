import Foundation
import WebKit

// MARK: - 搜索指令

/// Sent by the parent to navigate between search matches.
enum SearchAction: Equatable {
    case next
    case prev
}

/// 一次性的搜索指令。
///
/// 渲染器不再随文件重建之后，只传「下一个」这个动作本身区分不出「这是一条新指令」
/// 还是「上一条已经被执行过了」——每次 `updateNSView` 都会重新看到它，于是按一次 ⌘G
/// 会变成按好几次。所以每条指令带一个自增编号，视图记住自己处理到几号。
struct SearchCommand: Equatable {
    let action: SearchAction
    let id: Int
}

/// 指令去重闸门。
///
/// 新建的视图用「当前编号」开局：换文件时上一条旧指令还挂在状态里，新视图不该把它
/// 当成自己的任务再跑一遍。
struct SearchCommandGate {
    private var handled: Int

    init(seen command: SearchCommand?) {
        handled = command?.id ?? -1
    }

    /// 是没执行过的新指令就返回动作，否则返回 nil。
    mutating func take(_ command: SearchCommand?) -> SearchAction? {
        guard let command, command.id != handled else { return nil }
        handled = command.id
        return command.action
    }
}

// MARK: - 滚动位置记忆

/// 每个文件滚到哪了。
///
/// 长驻 WebView 复用之后，「读了一半去看别的，再回来」应该回到原来的位置——不然复用
/// 省下来的一百多毫秒又会被用户自己重新滚一遍。
///
/// 只记在内存里：跨启动恢复位置没有意义（用户不会记得上次滚到哪），也不给 UserDefaults
/// 塞垃圾。只在主线程访问——SwiftUI 的 `updateNSView` 与 `WKScriptMessageHandler` 回调
/// 都在主线程上。
final class ScrollMemory {
    static let shared = ScrollMemory()

    private var offsets: [String: Double] = [:]
    private var order: [String] = []
    /// 上限只用来防止长会话无限涨，正常用不到
    private let limit = 200

    func offset(for key: String) -> Double {
        offsets[key] ?? 0
    }

    func remember(_ y: Double, for key: String) {
        guard !key.isEmpty else { return }
        if offsets.updateValue(y, forKey: key) == nil {
            order.append(key)
        }
        while order.count > limit {
            offsets.removeValue(forKey: order.removeFirst())
        }
    }
}

// MARK: - 注入页面的脚本

/// 页面侧与原生侧的共同约定，三个 WebView 渲染器（HTML 文件 / Markdown / 代码）共用。
enum WebContentScript {
    /// 页面把滚动位置上交给原生侧用的消息名
    static let scrollHandlerName = "doupiScroll"

    /// 持续上报滚动位置。
    ///
    /// 不做节流：macOS 的 scroll 事件本身就是按帧合并的，一帧最多一条消息。
    /// 也刻意不用 requestAnimationFrame——页面不在可见窗口里、或者 app 不活跃时，rAF
    /// 可能一帧都不触发，位置就丢了；定时器和事件没这个问题。
    static let reportScroll = """
    (function(){ if(window.__doupiScrollHooked) return; window.__doupiScrollHooked=true;
      function send(){ try{ window.webkit.messageHandlers.\(scrollHandlerName).postMessage(window.scrollY||0); }catch(e){} }
      window.addEventListener('scroll', send, {passive:true});
      window.addEventListener('load', send);
    })();
    """

    /// 把页面钉在恢复位置上，直到它稳定下来。
    ///
    /// 新页面是从第 0 行开始画的，等 `didFinish` 之后再 scrollTo 已经晚了——中间那几帧
    /// 用户看到的就是「先闪到顶部再弹回去」。所以从 documentStart 就挂上，反复纠偏：
    /// 页面长高（图片、字体、异步内容）也一直钉着。用户自己一动就把控制权交还给他。
    static func pinScroll(to y: Double) -> String {
        guard y > 0 else { return "" }
        return """
        (function(){ var y=\(number(y)), until=Date.now()+2000;
          function apply(){ try{ if(Math.abs((window.scrollY||0)-y)>1) window.scrollTo(0,y); }catch(e){} }
          apply();
          ['DOMContentLoaded','load'].forEach(function(t){ window.addEventListener(t, apply); });
          var timer=setInterval(function(){ apply(); if(Date.now()>=until) clearInterval(timer); }, 16);
          if(window.requestAnimationFrame){
            (function loop(){ apply(); if(Date.now()<until) requestAnimationFrame(loop); })();
          }
          ['wheel','keydown','mousedown','touchstart'].forEach(function(t){
            window.addEventListener(t, function(){ until=0; clearInterval(timer); }, {passive:true, once:true});
          });
        })();
        """
    }

    static func number(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

/// 长驻 WebView 的页面身份：知道现在展示的是哪个文件，并把页面持续上报的滚动位置存起来。
final class ContentPageState: NSObject, WKScriptMessageHandler {
    private(set) var key = ""

    func begin(_ key: String) {
        self.key = key
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == WebContentScript.scrollHandlerName,
              let y = message.body as? NSNumber
        else { return }
        ScrollMemory.shared.remember(y.doubleValue, for: key)
    }
}

// MARK: - Markdown 壳的种类

/// 打开一份 markdown 需要哪种壳。
///
/// 有 mermaid 图才需要那份 3.4 MB 的渲染器；没有图的文档跟着一起扛，就是每次开文件
/// 白等一百毫秒。壳按种类各留一份长驻页面，跨种类切换时才整页重载。
enum MarkdownShellKind: Equatable {
    case plain
    case mermaid

    static func needed(for markdown: String) -> MarkdownShellKind {
        markdown.split(separator: "\n", omittingEmptySubsequences: false).contains(where: hasMermaidFence)
            ? .mermaid
            : .plain
    }

    /// 这一行是不是 ```mermaid / ~~~mermaid 围栏（允许前置缩进和围栏后的多余空格）。
    private static func hasMermaidFence(_ line: Substring) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") else { return false }
        let info = trimmed.drop(while: { $0 == "`" || $0 == "~" }).trimmingCharacters(in: .whitespaces)
        return info.split(separator: " ").first == "mermaid"
    }
}
