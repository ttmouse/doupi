import Foundation

/// 从文件内容里还原一个像样的名字。
///
/// AI 导出的页面常常都叫 `preview.html`，下载撞名时系统再补一个 `(1)` `(2)`，
/// 光看文件名分不出是哪个文档。名字其实就写在文件自己里（HTML 的 `<title>`、
/// Markdown 的一级标题），读出来显示即可——**只读，不改磁盘上任何东西**。
///
/// 只在文件名本身没有信息量时才去读内容，其余一律不做多余 I/O。
enum DocumentTitles {

    /// 内容标题；没有、读不出来、或者跟文件名一样没信息量时返回 nil。
    static func title(of url: URL) -> String? {
        let key = cacheKey(for: url)
        if let cached = cache.object(forKey: key as NSString) {
            return cached.length == 0 ? nil : cached as String
        }
        let resolved = extract(from: url)
        cache.setObject((resolved ?? "") as NSString, forKey: key as NSString)
        return resolved
    }

    /// 侧边栏行上显示的名字：文件名没信息量时用内容标题，否则直接用文件名（不读磁盘）。
    static func displayName(of url: URL) -> String {
        let fileName = url.lastPathComponent
        guard needsTitle(fileName) else { return fileName }
        return title(of: url) ?? fileName
    }

    /// 这个文件名是不是没信息量到需要去读内容。
    /// 去掉重名后缀与尾部日期后，主干落进通用名清单（或者短得没有意义）就算。
    static func needsTitle(_ fileName: String) -> Bool {
        let stem = (fileName as NSString).deletingPathExtension
        let trimmed = collisionSuffix.stringByReplacingMatches(
            in: stem,
            range: NSRange(stem.startIndex..<stem.endIndex, in: stem),
            withTemplate: ""
        )
        let base = trailingStamp.stringByReplacingMatches(
            in: trimmed,
            range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed),
            withTemplate: ""
        )
        .trimmingCharacters(in: CharacterSet(charactersIn: " _-"))
        .lowercased()
        return base.count <= 2 || genericStems.contains(base)
    }

    // MARK: - 内容读取

    private static func extract(from url: URL) -> String? {
        guard let text = head(of: url) else { return nil }
        let candidate: String?
        switch url.pathExtension.lowercased() {
        case "html", "htm":
            candidate = match(htmlTitle, in: text).map(decodingEntities)
        case "md", "markdown":
            candidate = match(markdownHeading, in: text)
        default:
            candidate = nil
        }
        guard let raw = candidate else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2, cleaned.count <= 120 else { return nil }
        // 标题跟文件名一样（或只是多了个重名后缀）就没带来任何新信息
        let stem = (url.lastPathComponent as NSString).deletingPathExtension.lowercased()
        guard cleaned.lowercased() != stem, !genericTitles.contains(cleaned.lowercased()) else { return nil }
        return cleaned
    }

    private static func head(of url: URL, limit: Int = 64 * 1024) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit), !data.isEmpty else { return nil }
        // 定长截断很可能把最后一个多字节字符切一半，
        // 那时整块字节就不是合法 UTF-8，直接用 String(data:encoding:) 会全部失败。
        // 所以先按页面声明的编码解（容错尾部），再退到宽松 UTF-8——坏字节最多变成一个替换字符，
        // 不影响把 <title> 读出来。
        if let declared = declaredEncoding(in: data), let text = decode(data, as: declared) {
            return text
        }
        if let text = decode(data, as: .utf8) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    /// 先严格解；失败就逐步丢掉尾部字节再试，处理截断在字符中间的情况。
    private static func decode(_ data: Data, as encoding: String.Encoding) -> String? {
        if let text = String(data: data, encoding: encoding) { return text }
        for dropped in 1...3 where data.count > dropped {
            if let text = String(data: data.dropLast(dropped), encoding: encoding) { return text }
        }
        return nil
    }

    /// 页面自己声明的字符集（`<meta charset=gbk>`）。
    private static func declaredEncoding(in data: Data) -> String.Encoding? {
        guard let probe = String(data: data.prefix(4096), encoding: .isoLatin1),
              let declared = match(charset, in: probe)
        else { return nil }
        switch declared.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")) {
        case "utf-8", "utf8": return .utf8
        case "gbk", "gb2312", "gb18030": return gb18030
        case "big5": return big5
        case "iso-8859-1", "latin1": return .isoLatin1
        default: return nil
        }
    }

    private static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    private static let big5 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue)
        )
    )

    private static func match(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, range: range), result.numberOfRanges > 1,
              let captured = Range(result.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }

    /// 解常见的命名实体，再解数字实体；解不出来的原样留着，不猜。
    private static func decodingEntities(_ text: String) -> String {
        var result = text
        for (entity, replacement) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                      ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
                                      ("&nbsp;", " "), ("&mdash;", "—"), ("&ndash;", "–")] {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }

        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        var decoded = ""
        var cursor = result.startIndex
        numericEntity.enumerateMatches(in: result, range: range) { match, _, _ in
            guard let match, let found = Range(match.range, in: result) else { return }
            decoded += result[cursor..<found.lowerBound]
            let body = result[found].dropFirst(2).dropLast()
            let code: UInt32? = body.lowercased().hasPrefix("x")
                ? UInt32(body.dropFirst(), radix: 16)
                : UInt32(body)
            if let code, let scalar = Unicode.Scalar(code) {
                decoded.append(Character(scalar))
            } else {
                decoded += result[found]
            }
            cursor = found.upperBound
        }
        decoded += result[cursor...]
        return decoded
    }

    private static func cacheKey(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let stamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let size = values?.fileSize ?? 0
        return "\(url.standardizedFileURL.path)|\(stamp)|\(size)"
    }

    private static let cache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 512
        return cache
    }()

    private static let genericStems: Set<String> = [
        "preview", "index", "document", "doc", "output", "untitled", "page", "file",
        "download", "artifact", "result", "answer", "reply", "new", "copy",
        "无标题", "未命名", "新建文档", "下载", "文档", "页面", "预览",
        "doubao_html", "chatgpt", "claude", "gemini", "deepseek", "kimi",
    ]

    private static let genericTitles: Set<String> = [
        "preview", "untitled", "document", "无标题", "未命名文档", "新建文档",
        "index", "output", "new page", "page",
    ]

    /// `preview (1)` → `preview`
    private static let collisionSuffix = regex(#"\s*[\(\（]\d+[\)\）]$"#)
    /// `doubao_html_20260909_144141` → `doubao_html`
    private static let trailingStamp = regex(#"[_\- ]\d{4,8}(?:[_\- ]\d{4,6})*$"#)
    private static let htmlTitle = regex(#"<title[^>]*>(.*?)</title>"#,
                                         options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let markdownHeading = regex(#"(?m)^#{1,2}[ \t]+(.+?)[ \t]*$"#)
    private static let numericEntity = regex(#"&#(?:x[0-9a-fA-F]+|\d+);"#)
    private static let charset = regex(#"charset\s*=\s*[\"']?([\w\-]+)"#, options: [.caseInsensitive])

    private static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            preconditionFailure("正则无法编译：\(pattern)")
        }
        return regex
    }
}
