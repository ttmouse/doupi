import Foundation

/// Lightweight value-type holding metadata about a dropped / opened file.
struct FileInfo: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let name: String
    let ext: String
    let size: Int64

    // MARK: - Computed

    var sizeFormatted: String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: size)
    }

    var typeBadge: String {
        if isHTML { return "HTML" }
        if isCode { return ext.uppercased() }
        if isImage { return "IMG" }
        if isPDF { return "PDF" }
        if ext.lowercased() == "txt" { return "TXT" }
        if isMarkdown { return "MD" }
        return ext.uppercased()
    }

    var isRenderable: Bool { isHTML || isMarkdown || isCode || isImage || isPDF || isText }

    // MARK: - Type checks

    var isHTML: Bool {
        ["html", "htm"].contains(ext.lowercased())
    }

    var isTSX: Bool {
        ["tsx", "jsx"].contains(ext.lowercased())
    }

    var isCode: Bool {
        Self.codeExtensions.contains(ext.lowercased())
    }

    var isImage: Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tiff", "tif", "ico"]
            .contains(ext.lowercased())
    }

    var isText: Bool { ext.lowercased() == "txt" }

    var isPDF: Bool { ext.lowercased() == "pdf" }

    var isMarkdown: Bool {
        ["md", "markdown"].contains(ext.lowercased())
    }

    /// highlight.js language class (or "plaintext").
    var highlightLanguage: String {
        Self.map[ext.lowercased()] ?? "plaintext"
    }

    // MARK: - Private

    private static let codeExtensions: Set<String> = [
        "tsx", "jsx", "js", "ts", "css", "scss", "less",
        "json", "yaml", "yml", "py", "go", "rs", "md", "markdown",
        "sql", "sh", "bash", "zsh", "toml", "xml",
        "php", "rb", "java", "c", "cpp", "h", "hpp",
        "swift", "kt", "scala", "pl", "lua", "r", "dart",
        "fs", "fsx", "svelte", "vue", "astro",
        "mjs", "cjs", "mts", "cts",
    ]

    private static let map: [String: String] = [
        // highlight.js 标准版不含 tsx/jsx，映射到 typescript/javascript
        "tsx": "typescript", "jsx": "javascript",
        "js": "javascript", "ts": "typescript",
        "css": "css", "scss": "scss", "less": "less",
        "json": "json", "yaml": "yaml", "yml": "yaml",
        "py": "python", "go": "go", "rs": "rust",
        "md": "markdown", "markdown": "markdown",
        "sql": "sql", "sh": "bash", "bash": "bash", "zsh": "bash",
        "toml": "toml", "xml": "xml",
        "html": "html", "htm": "html",
        "php": "php", "rb": "ruby",
        "java": "java", "c": "c", "cpp": "cpp",
        "h": "c", "hpp": "cpp",
        "swift": "swift", "kt": "kotlin",
        "scala": "scala", "pl": "perl", "lua": "lua",
        "r": "r", "dart": "dart",
        "svelte": "svelte", "vue": "vue", "astro": "astro",
        "mjs": "javascript", "cjs": "javascript",
        "mts": "typescript", "cts": "typescript",
    ]

    // MARK: - Factory

    static func from(url: URL) -> Self? {
        guard url.isFileURL else { return nil }
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = resourceValues?.fileSize ?? 0
        let name = url.lastPathComponent
        let ext  = url.pathExtension
        return FileInfo(url: url, name: name, ext: ext, size: Int64(fileSize))
    }
}
