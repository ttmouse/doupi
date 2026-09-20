import Foundation

/// Drives search bar visibility and state across the app.
/// Plain struct so @State can track any property mutation directly.
struct SearchState {
    var isVisible = false
    var query = ""
    var matchCount = 0
    var currentMatch = 0

    /// Set by navigateSearch to tell views which direction to go.
    var pendingCommand: SearchCommand? = nil

    /// 指令编号：长驻 WebView 靠它区分「这是一条新指令」和「上一条已经执行过了」。
    var commandSeq = 0
}
