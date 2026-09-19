import Combine
import Foundation

/// 版本族 + 内容还原名称的回归检查。
/// 用真实的文件名和真实的磁盘文件跑，不靠模拟。
@main
struct VersionFamilyChecks {
    @MainActor
    static func main() async throws {
        try checkMarkers()
        try checkCollisionSuffixIsNotAVersion()
        try checkGrouping()
        try checkCurrentVersion()
        try checkSelectionStore()
        try checkDocumentTitles()
        print("PASS: all version family regression checks")
    }

    // MARK: - 标记识别

    @MainActor
    static func checkMarkers() throws {
        // 生产者/用户主动加的修订标记
        let stripped: [(String, String)] = [
            ("ai_dev_command_dictionary_tab_workbench_v14.html", "ai_dev_command_dictionary_tab_workbench.html"),
            ("skills_learning_doc_v2.html", "skills_learning_doc.html"),
            ("rize_ai_time_tracking_analysis_optimized.html", "rize_ai_time_tracking_analysis.html"),
            ("07-wecom-integration.bak-202608091000.html", "07-wecom-integration.html"),
            ("责任主体运营流程澄清_持续履约版_最终结论.html", "责任主体运营流程澄清_持续履约版.html"),
            ("智控人控_基层安全监管新模式_概念与业务逻辑审计报告 new.html",
             "智控人控_基层安全监管新模式_概念与业务逻辑审计报告.html"),
            ("报告-最终.html", "报告.html"),
            ("note_副本.md", "note.md"),
        ]
        for (input, expected) in stripped {
            let actual = VersionFamilies.familyName(of: input)
            precondition(actual == expected, "\(input) → \(actual)，期望 \(expected)")
        }

        // 不该被误伤的：语义变体名、序号前缀、别的扩展名、标记不在结尾
        let untouched = [
            "服务团队AI机会评估记录_客户调研版.md",   // 语义变体，不是版本标记
            "责任主体运营流程澄清_持续履约版.html",
            "01-core-graph.html",
            "brandnew.html",
            "renew-2026.md",
            "brand_new_thing.md",
            "AI销售系统与销售抵触：原理、调整与落地建议.html",
        ]
        for name in untouched {
            let actual = VersionFamilies.familyName(of: name)
            precondition(actual == name, "\(name) 被误伤成 \(actual)")
        }

        precondition(VersionFamilies.familyName(of: "报告.html") == "报告.html",
                     "没有标记的文件名不该被动过一个字")
        // 同样的词干不同扩展名不是同一份产物
        precondition(VersionFamilies.familyName(of: "preview.html")
                     != VersionFamilies.familyName(of: "preview.md"),
                     "扩展名不同不应归为一个族")
        print("PASS: 只认主动加的修订标记，语义变体名与序号前缀不被误伤")
    }

    // MARK: - 重名后缀不是版本（用户 2026-09-19 纠正）

    @MainActor
    static func checkCollisionSuffixIsNotAVersion() throws {
        // `preview (1).html` ~ `preview (5).html` 是 5 份**不同的**文档
        // 下载时撞了同一个默认名，系统给补的序号。当成版本合并 = 藏掉真实文档。
        let collisions = [
            "preview.html", "preview (1).html", "preview (2).html",
            "preview (3).html", "preview (4).html", "preview (5).html",
            "方案（2）.md",
            "多客户AI项目工作系统-产品方案-重构评审稿 (1).md",
        ]
        for name in collisions {
            let actual = VersionFamilies.familyName(of: name)
            precondition(actual == name, "重名后缀被当成版本标记：\(name) → \(actual)")
        }

        // 同一批文件必须落成同样多的族，一个都不能藏
        let files = collisions.map { LibraryFile(sourceURL: URL(fileURLWithPath: "/tmp/\($0)")) }
        let families = VersionFamilies.families(in: files)
        precondition(families.count == collisions.count,
                     "\(collisions.count) 个撞名文件应各自成族，实得 \(families.count)")
        precondition(families.allSatisfy { !$0.isFamily }, "撞名文件之间不该被判为版本族")
        print("PASS: 重名后缀不当作版本，撞名文件一个不藏")
    }

    // MARK: - 归并

    @MainActor
    static func checkGrouping() throws {
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // 真正的版本族：_vN 递增
        var versions: [LibraryFile] = []
        for (index, name) in ["方案_v1.html", "方案_v2.html", "方案_v3.html"].enumerated() {
            versions.append(LibraryFile(sourceURL: try write(name, in: root, daysAgo: 30 - Double(index))))
        }
        let orphan = LibraryFile(sourceURL: try write("孤独文件.html", in: root, daysAgo: 1))
        let other = LibraryFile(sourceURL: try write("方案.md", in: root, daysAgo: 2))

        let families = VersionFamilies.families(in: versions + [orphan, other])
        precondition(families.count == 3, "期望 3 个族（方案 / 孤独文件 / 方案.md），实得 \(families.count)")

        let plan = try unwrap(families.first { $0.name == "方案.html" })
        precondition(plan.isFamily && plan.members.count == 3, "方案应有 3 版，实得 \(plan.members.count)")
        precondition(plan.members.map(\.name) == ["方案_v1.html", "方案_v2.html", "方案_v3.html"],
                     "成员应按修改时间升序：\(plan.members.map(\.name))")
        precondition(plan.latest.name == "方案_v3.html", "最新一版应是 方案_v3.html")

        let orphanFamily = try unwrap(families.first { $0.name == "孤独文件.html" })
        precondition(!orphanFamily.isFamily && orphanFamily.members.count == 1,
                     "单成员族照样返回，由调用方决定显示")

        // 行序取首次出现位置，且 id 跨调用稳定（否则每轮刷新行身份会跳）
        let again = VersionFamilies.families(in: versions + [orphan, other])
        precondition(again.map(\.id) == families.map(\.id), "族 id 必须稳定：\(again.map(\.id))")
        precondition(Set(again.map(\.id)).count == again.count, "族 id 不能重复")
        precondition(plan.id.contains(root.path), "族 id 应绑定磁盘目录：\(plan.id)")
        print("PASS: 同目录同族归并，跨扩展名/单成员不误并，行序与 id 稳定")
    }

    // MARK: - 当前版本

    @MainActor
    static func checkCurrentVersion() throws {
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let old = LibraryFile(sourceURL: try write("报告_v1.html", in: root, daysAgo: 10))
        let mid = LibraryFile(sourceURL: try write("报告_v2.html", in: root, daysAgo: 5))
        let new = LibraryFile(sourceURL: try write("报告_v3_最终结论.html", in: root, daysAgo: 1))
        let family = try unwrap(VersionFamilies.families(in: [old, mid, new])
            .first { $0.name == "报告.html" })
        precondition(family.members.count == 3, "三版应聚成一个族")

        precondition(VersionFamilies.current(of: family, chosen: nil).name == "报告_v3_最终结论.html",
                     "默认应取最近修改的一版")
        // 钉过 → 用钉的（_最终结论 这种名字说明「最新」未必是「我要的」）
        precondition(VersionFamilies.current(of: family, chosen: "报告_v2.html").name == "报告_v2.html",
                     "用户钉住的版本优先于最新")
        precondition(VersionFamilies.current(of: family, chosen: "已删除.html").name == "报告_v3_最终结论.html",
                     "钉住的版本消失后应回落到最新")
        print("PASS: 默认取最新，用户钉住优先，钉住失效自动回落")
    }

    // MARK: - 选择存储

    @MainActor
    static func checkSelectionStore() throws {
        let suite = "doupi.version-selection.check.\(UUID().uuidString)"
        let defaults = try unwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = VersionSelectionStore(defaults: defaults)
        precondition(store.chosen(for: "family") == nil, "初始应为自动取最新")

        store.choose("报告_v2.html", for: "family")
        precondition(store.chosen(for: "family") == "报告_v2.html", "选择应立即可读")
        precondition(VersionSelectionStore(defaults: defaults).chosen(for: "family") == "报告_v2.html",
                     "选择应持久化")

        store.choose(nil, for: "family")
        precondition(store.chosen(for: "family") == nil, "传 nil 应恢复自动取最新")
        print("PASS: 版本选择可持久化，也能恢复成自动取最新")
    }

    // MARK: - 从内容还原名称

    @MainActor
    static func checkDocumentTitles() throws {
        let root = try makeFixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // 只有没信息量的文件名才去读内容
        precondition(DocumentTitles.needsTitle("preview (3).html"), "preview (3) 没有信息量")
        precondition(DocumentTitles.needsTitle("preview.html"), "preview 没有信息量")
        precondition(DocumentTitles.needsTitle("doubao_html_20260909_144141.html"), "导出名+时间戳没有信息量")
        precondition(DocumentTitles.needsTitle("无标题.html"), "无标题 没有信息量")
        precondition(!DocumentTitles.needsTitle("应急管理业务_ReBAC权限设计落地方案.html"),
                     "有意义的文件名不该触发读磁盘")
        precondition(!DocumentTitles.needsTitle("应急管理产品架构交互示意图 (1).tsx"),
                     "有意义的文件名加个撞名后缀，名字仍然有信息量")
        precondition(!DocumentTitles.needsTitle("20260813-镇街端使用日报-20260811.html"),
                     "日期前缀不算没信息量")

        // HTML 标题
        let titled = try write("preview (1).html",
                               in: root,
                               contents: "<html><head><title>应急管理业务 AI 化路线图</title></head><body>x</body></html>")
        precondition(DocumentTitles.title(of: titled) == "应急管理业务 AI 化路线图",
                     "应读出 HTML 标题，实得 \(DocumentTitles.title(of: titled) ?? "nil")")
        precondition(DocumentTitles.displayName(of: titled) == "应急管理业务 AI 化路线图",
                     "没信息量的文件名应换成内容标题")

        // 有意义的文件名不读内容，原样返回
        let meaningful = try write("有意义的文件名.html", in: root,
                                   contents: "<title>完全不一样的东西</title>")
        precondition(DocumentTitles.displayName(of: meaningful) == "有意义的文件名.html",
                     "文件名有意义时不该被内容标题顶掉")

        // 实体与数字实体
        let entity = try write("preview (2).html", in: root,
                              contents: "<title>A &amp; B &#8212; C &#x4E2D;</title>")
        precondition(DocumentTitles.title(of: entity) == "A & B — C 中",
                     "实体应解出来，实得 \(DocumentTitles.title(of: entity) ?? "nil")")

        // 标题本身也是通用名 → 等于没还原出来
        let generic = try write("preview (3).html", in: root, contents: "<title>preview</title>")
        precondition(DocumentTitles.title(of: generic) == nil, "通用标题不算还原出名字")
        precondition(DocumentTitles.displayName(of: generic) == "preview (3).html",
                     "还原不出来就退回真实文件名")

        // 没有标题 → 退回文件名
        let bare = try write("preview (4).html", in: root, contents: "<html><body>没有标题</body></html>")
        precondition(DocumentTitles.displayName(of: bare) == "preview (4).html", "没有标题就退回文件名")

        // Markdown 一级标题
        let note = try write("preview.md", in: root,
                             contents: "---\nfront: matter\n---\n\n# 我的会议笔记\n\n正文")
        precondition(DocumentTitles.title(of: note) == "我的会议笔记",
                     "应读出 Markdown 一级标题，实得 \(DocumentTitles.title(of: note) ?? "nil")")

        // 超过长度上限的标题不采用（多半是塞了一整段正文）
        let huge = try write("preview (5).html", in: root,
                             contents: "<title>\(String(repeating: "长", count: 200))</title>")
        precondition(DocumentTitles.title(of: huge) == nil, "过长的标题应丢弃")

        // 定长截断会切在多字节字符中间：那时整块字节不是合法 UTF-8。
        // 曾经因此整个解码失败，把本来有标题的页面当成“还原不出来”。
        let bigBody = String(repeating: "中文正文内容", count: 12_000) // 远超头部读取窗口
        let truncated = try write("preview (6).html", in: root,
                                  contents: "<title>截断边界上的标题</title><body>\(bigBody)</body>")
        precondition(DocumentTitles.title(of: truncated) == "截断边界上的标题",
                     "尾部被截断在多字节字符中间时仍应读出标题")

        // 标题藏在一大堆前置内容之后
        let latePadding = String(repeating: "x", count: 20_000)
        let late = try write("preview (7).html", in: root,
                             contents: "<head>\(latePadding)<title>来得很晚的标题</title></head>")
        precondition(DocumentTitles.title(of: late) == "来得很晚的标题", "标题在 20KB 之后也应读得到")

        // 非 UTF-8 页面：按自己声明的字符集解
        let gbText = "<html><head><meta charset=\"gbk\"><title>国产编码的标题</title></head></html>"
        let gbURL = root.appendingPathComponent("preview (8).html")
        let gbData = gbText.data(using: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))))
        try unwrap(gbData).write(to: gbURL)
        precondition(DocumentTitles.title(of: gbURL) == "国产编码的标题",
                     "GBK 页面应按声明的字符集解，实得 \(DocumentTitles.title(of: gbURL) ?? "nil")")
        print("PASS: 内容标题可还原，通用名/无标题/超长标题都能退回真实文件名")
    }

    // MARK: - 夹具

    static func makeFixtureRoot() throws -> URL {
        let root = URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath()
            .appendingPathComponent("doupi-version-families-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @discardableResult
    static func write(_ name: String, in root: URL,
                      contents: String = "# Fixture", daysAgo: Double = 0) throws -> URL {
        let url = root.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        if daysAgo > 0 {
            let when = Date().addingTimeInterval(-daysAgo * 86_400)
            try FileManager.default.setAttributes([.modificationDate: when], ofItemAtPath: url.path)
        }
        return url.standardizedFileURL
    }

    static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { preconditionFailure("Expected a value") }
        return value
    }
}
