import Foundation

/// Converts TSX/JSX content into previewable HTML by stripping
/// JavaScript/TypeScript syntax and keeping the JSX markup.
struct TSXPreview {

    /// Raw file content → HTML string suitable for WKWebView.
    static func render(_ raw: String) -> String {
        var lines = raw.components(separatedBy: "\n")
        var inCodeBlock = false // track template literals with backticks

        // 1. Strip import/export/require lines
        lines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("import ") || trimmed.hasPrefix("export ") || trimmed.hasPrefix("require(") {
                return false
            }
            return true
        }

        // 2. Process each line: strip JS logic, keep JSX
        let processed = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines after stripping
            if trimmed.isEmpty { return "" }

            // Skip pure JS constructs
            if trimmed.hasPrefix("const ") || trimmed.hasPrefix("let ") || trimmed.hasPrefix("var ") { return "" }
            if trimmed.hasPrefix("function ") || trimmed.hasPrefix("return ") || trimmed.hasPrefix("=>") { return "" }
            if trimmed.hasPrefix("if ") || trimmed.hasPrefix("else") || trimmed.hasPrefix("switch") { return "" }
            if trimmed.hasPrefix("try ") || trimmed.hasPrefix("catch") { return "" }
            if trimmed.hasPrefix("interface ") || trimmed.hasPrefix("type ") || trimmed.hasPrefix("enum ") { return "" }
            if trimmed.hasPrefix("useState") || trimmed.hasPrefix("useEffect") || trimmed.hasPrefix("use") { return "" }
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") { return "" }

            // Strip template literal backtick lines (code blocks in JSX)
            if trimmed.hasPrefix("`") && trimmed.hasSuffix("`") { return "" }

            return line
        }

        var html = processed.joined(separator: "\n")

        // 3. Clean up embedded JS/TS patterns
        html = cleanJSX(html)

        // 4. Add Tailwind-style reset + base styles
        return wrapInHTML(html)
    }

    /// Remove common JS expressions and props from JSX content.
    private static func cleanJSX(_ input: String) -> String {
        var result = input

        // Remove TypeScript type annotations: `: SomeType`
        // Be careful not to remove className, href, etc.
        result = result.replacingOccurrences(
            of: #":\s*(string|number|boolean|void|any|undefined|null|never|React\.\w+|JSX\.\w+|Record<[^>]+>|\[\s*\])"#,
            with: "",
            options: .regularExpression
        )

        // Remove generic type params: `<SomeType>` (but keep HTML tags)
        // Only remove `<>` that appear after identifiers
        result = result.replacingOccurrences(
            of: #"(\w+?)<(\w+(?:\[\])?(?:\s*\|\s*\w+(?:\[\])?)*)>"#,
            with: "$1",
            options: .regularExpression
        )

        // Remove JSX expression attributes with simple values: `prop={variable}`
        // Keep string literals and boolean props
        result = result.replacingOccurrences(
            of: #"\s+\w+=\{(?:[^}]*?(?:\([^)]*\))?[^}]*?)\}"#,
            with: "",
            options: .regularExpression
        )

        // Remove event handlers: onClick, onChange, onSubmit, onMouseOver, etc.
        result = result.replacingOccurrences(
            of: #"\s+on\w+=\{[^}]*\}"#,
            with: "",
            options: .regularExpression
        )

        // Remove ref/forwardRef/key props
        result = result.replacingOccurrences(
            of: #"\s+(ref|key|forwardedRef)=\{[^}]*\}"#,
            with: "",
            options: .regularExpression
        )

        // Replace select React-specific attrs with HTML equivalents
        let attrMap: [(String, String)] = [
            ("className=", "class="),
            ("htmlFor=", "for="),
            ("tabIndex=", "tabindex="),
            ("autoFocus", "autofocus"),
            ("autoComplete=", "autocomplete="),
            ("encType=", "enctype="),
            ("httpEquiv=", "http-equiv="),
            ("noValidate", "novalidate"),
            ("formNoValidate", "formnovalidate"),
            ("readOnly", "readonly"),
            ("srcSet=", "srcset="),
            ("suppressHydrationWarning", ""),
            ("dangerouslySetInnerHTML", ""),
        ]
        for (react, html) in attrMap {
            result = result.replacingOccurrences(of: react, with: html)
        }

        // Remove curly-brace expressions that survived: {...whatever}
        result = result.replacingOccurrences(
            of: #"\{[^}]*\}"#,
            with: "",
            options: .regularExpression
        )

        // Clean up double spaces and trailing whitespace
        result = result.replacingOccurrences(of: "  ", with: " ")
        result = result.replacingOccurrences(of: " >", with: ">")
        result = result.replacingOccurrences(of: "  ", with: " ")

        return result
    }

    /// Wrap processed content in a complete HTML document.
    private static func wrapInHTML(_ body: String) -> String {
        return """
        <!DOCTYPE html>
        <html lang="zh">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Preview</title>
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body {
            font-family: -apple-system, "PingFang SC", system-ui, sans-serif;
            background: #ffffff;
            color: #1d1d1f;
            padding: 24px;
            line-height: 1.6;
            -webkit-font-smoothing: antialiased;
          }
          img { max-width: 100%; height: auto; }
          pre { background: #f5f5f5; padding: 16px; border-radius: 8px; overflow-x: auto; }
          code { font-family: "SF Mono", Menlo, monospace; font-size: 13px; }
          table { border-collapse: collapse; width: 100%; }
          th, td { border: 1px solid #e0e0e0; padding: 8px 12px; text-align: left; }
          th { background: #f8f8f8; font-weight: 600; }
          a { color: #4A7A23; }
          a:hover { color: #7BC043; }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}
