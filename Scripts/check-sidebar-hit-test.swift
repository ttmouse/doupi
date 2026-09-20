import AppKit
import SwiftUI

/// 侧边栏「不可见 AppKit 宿主」的回归检查。
///
/// 保护一件事：键盘导航用的 AppKit 宿主盖在整个侧边栏上，它**不能**接管鼠标事件。
///
/// 之前这里返回的是普通 `NSView`，于是 hitTest 认领了整个侧边栏区域，
/// SwiftUI 收不到任何点击——折叠标题（置顶 / 文件 / 最近打开）点不动、行选不中、
/// 右键菜单和拖拽全部失灵，而界面上看不出任何异常（宿主视图是空的）。
/// 修复后宿主改成 `EventPassthroughView`（hitTest 返回 nil）。
///
/// 检查就用真实的 SwiftUI 事件链路：造一个带按钮的 SwiftUI 视图 + 同样的 overlay 宿主，
/// 往按钮位置投一次真实的 mouseDown/mouseUp，看按钮的 action 到底有没有跑。
@main
struct SidebarHitTestChecks {

    static func main() {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()

        checkHostIsPassthrough()
        checkClickReachesContent()

        print("OK: sidebar keyboard host does not swallow mouse events")
    }

    /// 宿主视图自己不认领命中测试，事件落到 SwiftUI 的 hosting view 上。
    private static func checkHostIsPassthrough() {
        let harness = makeHarness()
        let point = buttonPoint(in: harness.window)
        let hit = harness.window.contentView?.hitTest(point)
        expect(hit is NSHostingView<SidebarProbe>, "overlay host yields the click to SwiftUI (hit = \(String(describing: hit.map { type(of: $0) })))")
        harness.tearDown()
    }

    /// 真按一下：折叠标题这类 SwiftUI 按钮必须真的收到点击。
    private static func checkClickReachesContent() {
        let harness = makeHarness()
        clickButton(in: harness.window)
        expect(harness.probe.pressCount == 1, "a real click on the header button reaches the SwiftUI action")
        harness.tearDown()
    }

    // MARK: - Harness

    private final class Probe: ObservableObject { @Published var pressCount = 0 }

    /// 与侧边栏同样的结构：SwiftUI 内容 + 覆盖全区域的 AppKit 宿主。
    private struct SidebarProbe: View {
        @ObservedObject var probe: Probe

        var body: some View {
            VStack(spacing: 3) {
                Button { probe.pressCount += 1 } label: {
                    Text("置顶")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            .frame(width: 200, height: 300)
            .overlay { KeyboardHost() }
        }
    }

    /// 对应文件侧边栏里的 `SidebarKeyboardHandler`：监听靠 NSEvent monitor，
    /// 视图本身只负责存在，不该参与交互。
    private struct KeyboardHost: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView { EventPassthroughView(frame: .zero) }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    private final class Harness {
        let window: NSWindow
        let host: NSHostingView<SidebarProbe>
        let probe: Probe

        init(window: NSWindow, host: NSHostingView<SidebarProbe>, probe: Probe) {
            self.window = window
            self.host = host
            self.probe = probe
        }

        func tearDown() {
            window.orderOut(nil)
        }
    }

    private static func makeHarness() -> Harness {
        let probe = Probe()
        let host = NSHostingView(rootView: SidebarProbe(probe: probe))
        // 放到屏幕外：检查不该在用户眼前闪一个窗口。
        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: 200, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        pump(0.3)
        return Harness(window: window, host: host, probe: probe)
    }

    /// 标题按钮中心（窗口坐标，底部为原点：窗口高 300，标题占顶部 32pt）。
    private static func buttonPoint(in window: NSWindow) -> CGPoint {
        CGPoint(x: 100, y: 300 - 16)
    }

    private static func clickButton(in window: NSWindow) {
        let point = buttonPoint(in: window)
        let timestamp = ProcessInfo.processInfo.systemUptime
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: timestamp,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ) else { continue }
            NSApplication.shared.sendEvent(event)
        }
        pump(0.3)
    }

    private static func pump(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
        print("PASS: \(message)")
    }
}
