import Foundation

/// 侧边栏筛选条件：空白分隔的多个关键词，**全部命中**才算匹配。
///
/// 每个关键词可以落在文件名上，也可以落在它所在的任意一级文件夹名上——
/// 所以「AI 菜花」既能捞出 `菜花 · AI 销售` 整个文件夹里的东西，
/// 也能捞出名叫 `ai-sales-agent.html` 的文件。
///
/// 关键词之间是「且」不是「或」：写第二个词是为了收窄结果，不是为了放宽。
struct SearchQuery: Equatable {
    let terms: [String]

    init(_ raw: String) {
        // split 默认按所有 Unicode 空白切分，全角空格（中文输入法下很容易打出来）也算。
        terms = raw.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    var isEmpty: Bool { terms.isEmpty }

    /// 给用户看的回显，确认他把几个词理解成了几个条件。
    var displayText: String { terms.joined(separator: " · ") }

    /// 这个名字（文件名或文件夹名）能满足掉哪几个关键词。
    func satisfied(by name: String) -> Set<Int> {
        guard !isEmpty else { return [] }
        var hit: Set<Int> = []
        for (index, term) in terms.enumerated() where name.localizedCaseInsensitiveContains(term) {
            hit.insert(index)
        }
        return hit
    }

    /// 已经凑齐全部关键词了吗。
    func isFullySatisfied(by satisfied: Set<Int>) -> Bool {
        isEmpty || satisfied.count == terms.count
    }

    /// 文件名加上沿途文件夹已经满足的关键词，是否覆盖了全部关键词。
    func matches(fileName: String, satisfiedByPath: Set<Int>) -> Bool {
        isEmpty || isFullySatisfied(by: satisfiedByPath.union(satisfied(by: fileName)))
    }
}
