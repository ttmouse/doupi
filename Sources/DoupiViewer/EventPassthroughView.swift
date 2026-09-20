import AppKit

/// SwiftUI 里挂「只做监听、不参与交互」的 AppKit 宿主时用这个视图。
///
/// 普通 `NSView` 会在 hitTest 中认领自己覆盖的每一寸区域：它一旦作为 overlay 盖在
/// SwiftUI 内容上，底下所有鼠标事件都被它吃掉——点击、右键菜单、拖拽、hover 全部失灵，
/// 而且从界面上完全看不出来（视图是空的）。监听本身走 NSEvent 全局/本地 monitor，
/// 不依赖这个视图接收事件，所以这里直接放弃命中测试，把事件让给下层的 SwiftUI。
final class EventPassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
