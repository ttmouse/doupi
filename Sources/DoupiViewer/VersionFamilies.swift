import Combine
import Foundation

/// 一份产物的多个版本在侧边栏只占一行。
///
/// 版本标记来自真实使用：`preview (3).html`、`_v14`、`_最终结论`、`.bak-202608091000`。
/// 归并只发生在视图层——磁盘上的文件一个都不动，任何一版仍然可以单独打开、在访达中显示、
/// 重命名、删除、拖拽。
struct VersionFamily: Identifiable, Hashable {
    /// 磁盘目录 + 族名。跨虚拟文件夹与归档文件夹共享同一个 key，
    /// 所以「我选的是哪一版」跟着产物本身走，不跟着它在侧边栏里的位置走。
    let id: String
    /// 剥掉版本标记后剩下的族名，例如 `preview.html`。
    let name: String
    /// 按修改时间升序，最后一个是最新的一版。
    let members: [LibraryFile]

    var isFamily: Bool { members.count > 1 }
    var latest: LibraryFile { members[members.count - 1] }
}

/// 从文件名里认出「同一份产物的不同版本」。
enum VersionFamilies {

    /// 剥掉版本/副本标记后剩下的族名。
    ///
    /// 只认明确的版本标记，且只认结尾处的：`_持续履约版`、`_客户调研版` 这类语义变体名
    /// 照原样保留，否则不同用途的产物会被并成一份。
    static func familyName(of fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension
        let original = ext.isEmpty ? fileName : (fileName as NSString).deletingPathExtension
        var stem = original
        while true {
            let stripped = markerRegex
                .stringByReplacingMatches(
                    in: stem,
                    range: NSRange(stem.startIndex..<stem.endIndex, in: stem),
                    withTemplate: ""
                )
                .trimmingCharacters(in: CharacterSet(charactersIn: " _-"))
            if stripped == stem { break }
            guard !stripped.isEmpty else { return fileName }
            stem = stripped
        }
        guard stem != original, !stem.isEmpty else { return fileName }
        return ext.isEmpty ? stem : stem + "." + ext.lowercased()
    }

    /// 同一目录下按族归并。单成员的族照样返回，由调用方决定怎么显示。
    /// 族的顺序取任一成员在原始列表里的首次出现位置，保证行序稳定。
    static func families(in files: [LibraryFile]) -> [VersionFamily] {
        var order: [String] = []
        var grouped: [String: [LibraryFile]] = [:]
        for file in files {
            let name = familyName(of: file.name)
            if grouped[name] == nil { order.append(name) }
            grouped[name, default: []].append(file)
        }
        return order.map { name in
            var members = grouped[name] ?? []
            if members.count > 1 {
                members.sort { modifiedAt($0.sourceURL) < modifiedAt($1.sourceURL) }
            }
            let key = members[0].sourceURL.deletingLastPathComponent().path + "/" + name
            return VersionFamily(id: key, name: name, members: members)
        }
    }

    /// 当前版本：用户钉过就用钉的，没钉过用最近修改的那一版。
    static func current(of family: VersionFamily, chosen: String?) -> LibraryFile {
        if let chosen, let picked = family.members.last(where: { $0.name == chosen }) {
            return picked
        }
        return family.latest
    }

    private static func modifiedAt(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    /// 版本标记只在文件名结尾才有意义，所以每条都锚在 `$`；
    /// 词形标记要求一个分隔符前缀，避免 `brandnew` 这种词被误伤。
    ///
    /// **故意不认 `(1)` `(2)` 这类重名后缀**：AI 导出的页面常常都叫 `preview.html`，
    /// 下载撞名时系统自动加序号，那些是**不同的文档**，不是同一份的版本。
    /// 只认可生产者/用户主动添加的修订标记（`_v14`、`_最终结论`、`.bak-时间戳`）。
    private static let markerRegex: NSRegularExpression = {
        let alternatives = [
            #"[_\- ]v\d+(?:\.\d+)*"#, // _v14 / -v1.2
            #"[_\- ]ver(?:sion)?\d+"#, // _version2
            #"[_\- ](?:final|copy|new|old|updated?|latest|refactored|optimized)"#,
            #"[_\- ](?:最终结论|最终|定稿|终稿|最新|更新版|新版|旧版|修订版|副本)"#,
            #"\.bak-\d+"#, // 07-wecom-integration.bak-202608091000
        ]
        let pattern = alternatives.map { "(?:" + $0 + ")$" }.joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            preconditionFailure("版本标记正则无法编译：\(pattern)")
        }
        return regex
    }()
}

/// 用户手动钉住的「当前版本」：族 id → 文件名。
///
/// 只在用户真的挑过某一版时才有值；没有值就按修改时间取最新。选中的文件消失后
/// 自动回落到最新的一版，不留下悬空状态。
@MainActor
final class VersionSelectionStore: ObservableObject {
    static let shared = VersionSelectionStore()

    private static let key = "DoupiVersionSelection"

    @Published private(set) var choices: [String: String]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.choices = (defaults.dictionary(forKey: Self.key) as? [String: String]) ?? [:]
    }

    func chosen(for familyID: String) -> String? {
        choices[familyID]
    }

    /// 传 nil 表示恢复成「自动取最新」。
    func choose(_ fileName: String?, for familyID: String) {
        guard choices[familyID] != fileName else { return }
        if let fileName {
            choices[familyID] = fileName
        } else {
            choices.removeValue(forKey: familyID)
        }
        defaults.set(choices, forKey: Self.key)
    }
}
