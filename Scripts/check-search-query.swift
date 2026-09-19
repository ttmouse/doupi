import Foundation

/// 侧边栏多关键词筛选的回归检查。
@main
struct SearchQueryChecks {
    static func main() {
        checkParsing()
        checkSingleTermUnchanged()
        checkAllTermsMustMatch()
        checkTermsCanLandOnDifferentLevels()
        checkEmptyQueryMatchesEverything()
        print("PASS: all search query regression checks")
    }

    // MARK: - 拆分

    static func checkParsing() {
        precondition(SearchQuery("AI 菜花").terms == ["AI", "菜花"], "空格分隔应拆成两个词")
        precondition(SearchQuery("  AI   菜花  ").terms == ["AI", "菜花"], "多余空白不该产生空词")
        // 中文输入法下很容易打出全角空格
        precondition(SearchQuery("AI\u{3000}菜花").terms == ["AI", "菜花"], "全角空格也要算分隔符")
        precondition(SearchQuery("AI\t菜花").terms == ["AI", "菜花"], "制表符也要算分隔符")
        precondition(SearchQuery("").terms.isEmpty, "空串没有关键词")
        precondition(SearchQuery("   ").isEmpty, "只有空白等于没筛选")
        precondition(SearchQuery("AI 菜花").displayText == "AI · 菜花", "回显应能看出被拆成几个条件")
        print("PASS: 关键词按空白拆分，全角空格与多余空白都能正确处理")
    }

    // MARK: - 单词不改行为

    static func checkSingleTermUnchanged() {
        let query = SearchQuery("ai")
        precondition(query.matches(fileName: "ai_sale.tsx", satisfiedByPath: []), "单词应命中")
        precondition(query.matches(fileName: "AI 销售", satisfiedByPath: []), "大小写不敏感")
        precondition(query.matches(fileName: "b2b.html", satisfiedByPath: query.satisfied(by: "菜花 · AI 销售")),
                     "单词落在文件夹名上也应命中")
        precondition(!query.matches(fileName: "b2b.html", satisfiedByPath: []), "都不含就不命中")
        precondition(SearchQuery("菜花").matches(fileName: "ai_sales_agent.html",
                                                 satisfiedByPath: SearchQuery("菜花").satisfied(by: "菜花 · AI 销售")),
                     "中文单词与旧的子串匹配一致")
        print("PASS: 单个关键词的行为与改动前一致")
    }

    // MARK: - 必须全部命中

    static func checkAllTermsMustMatch() {
        let query = SearchQuery("AI 菜花")

        // 两个词都落在文件夹名上
        let salesFolder = query.satisfied(by: "菜花 · AI 销售")
        precondition(query.isFullySatisfied(by: salesFolder),
                     "「AI 菜花」应整体命中 菜花 · AI 销售 这个文件夹")
        precondition(query.matches(fileName: "b2b.html", satisfiedByPath: salesFolder),
                     "文件夹整体命中时，里面的文件都应命中")

        // 只命中一个词 → 不算
        let onlyAI = query.satisfied(by: "AI 与智能体")
        precondition(!query.matches(fileName: "ai_governance_assistant_demo.html", satisfiedByPath: onlyAI),
                     "只命中「AI」不该命中，否则「菜花」等于没写")
        let onlyCaihua = query.satisfied(by: "菜花 · AI 销售")
        precondition(!query.matches(fileName: "菜花调研记录.md", satisfiedByPath: []),
                     "只命中「菜花」不该命中")
        precondition(query.matches(fileName: "菜花调研记录.md", satisfiedByPath: onlyCaihua),
                     "两个词凑齐后应命中")

        // 顺序无关
        let reversed = SearchQuery("菜花 AI")
        precondition(reversed.isFullySatisfied(by: reversed.satisfied(by: "菜花 · AI 销售")),
                     "关键词顺序不该影响结果")

        // 重复词不要求出现两次（用户手滑，不是新条件）
        precondition(SearchQuery("AI AI").matches(fileName: "AI 与智能体", satisfiedByPath: []),
                     "重复关键词按一个算")
        print("PASS: 多关键词之间是「且」，缺一个就不算命中")
    }

    // MARK: - 关键词可以落在不同层级

    static func checkTermsCanLandOnDifferentLevels() {
        let query = SearchQuery("AI 菜花")

        // 一个词在某级文件夹，另一个词在下一级
        var satisfied: Set<Int> = []
        satisfied.formUnion(query.satisfied(by: "项目"))
        satisfied.formUnion(query.satisfied(by: "菜花"))
        satisfied.formUnion(query.satisfied(by: "AI 相关"))
        precondition(query.isFullySatisfied(by: satisfied), "关键词落在不同层级也应凑齐")

        // 一个词在文件夹，一个词在文件名
        let partial = query.satisfied(by: "菜花")
        precondition(query.matches(fileName: "AI 落地报告.html", satisfiedByPath: partial),
                     "一个词在文件夹、一个词在文件名，应命中")

        // 拿到的命中集合是「沿途累积」的，不是只看当前层
        let lower = SearchQuery("项目 报告")
        let inherited = lower.satisfied(by: "项目")
        precondition(lower.matches(fileName: "月度报告.html", satisfiedByPath: inherited),
                     "上层文件夹满足的词应传给下层文件")
        precondition(!lower.matches(fileName: "月度报告.html", satisfiedByPath: []),
                     "没有上层传下来的词就不该命中")
        print("PASS: 关键词可以落在文件名或任意一级文件夹名上，命中沿路径累积")
    }

    // MARK: - 空查询

    static func checkEmptyQueryMatchesEverything() {
        for raw in ["", "   ", "\t"] {
            let query = SearchQuery(raw)
            precondition(query.isEmpty, "\(raw.debugDescription) 应视为空查询")
            precondition(query.matches(fileName: "随便什么.html", satisfiedByPath: []),
                         "空查询不该过滤掉任何文件")
            precondition(query.isFullySatisfied(by: []), "空查询视为已满足")
        }
        print("PASS: 空查询不过滤任何文件")
    }
}
