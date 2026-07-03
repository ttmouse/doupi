import Foundation
import WebKit

/// Compiles TSX/JSX files via esbuild and renders them as a live web page.
struct TSXPreview {

    /// Returns a complete HTML document for previewing the TSX file.
    static func render(fileURL: URL) -> String {
        guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return errorPage("无法读取文件")
        }

        // Try to compile with esbuild
        let compiledJS = compileWithEsbuild(fileURL)

        if let js = compiledJS {
            // We could try to evaluate and render the data, but to keep it
            // robust and general-purpose, show source + compiled preview side by side.
            return buildPreviewPage(source: source, compiledJS: js, fileName: fileURL.lastPathComponent)
        } else {
            // Fallback: just syntax-highlight the source
            return buildSourceOnlyPage(source: source, fileName: fileURL.lastPathComponent)
        }
    }

    // MARK: - Esbuild Compilation

    private static func compileWithEsbuild(_ url: URL) -> String? {
        let esbuildPaths = [
            "/Users/douba/.npm-global/bin/esbuild",
            "/opt/homebrew/bin/esbuild",
            "/usr/local/bin/esbuild",
            "/usr/bin/esbuild",
        ]

        guard let esbuildPath = esbuildPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: esbuildPath)
        process.arguments = [
            url.path,
            "--format=esm",
            "--target=es2020",
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)
        return output
    }

    // MARK: - Full Preview Page (source + rendered data)

    private static func buildPreviewPage(source: String, compiledJS: String, fileName: String) -> String {
        let escapedSource = escapeHTML(source)
        let (cleanJS, dataVars) = extractDataVariables(compiledJS)

        // Build a JSON blob of the exported data for runtime rendering
        let dataInitScript = buildDataInitScript(compiledJS, dataVars: dataVars)

        return """
        <!DOCTYPE html>
        <html lang="zh">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Preview: \(escapeHTML(fileName))</title>
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css">
        <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body {
            font-family: -apple-system, "PingFang SC", "SF Pro", system-ui, sans-serif;
            background: #f8f7f4;
            color: #1d1d1f;
            line-height: 1.6;
          }
          .tabs {
            display: flex;
            border-bottom: 2px solid #e0ddd8;
            background: #f0eee9;
            position: sticky;
            top: 0;
            z-index: 10;
          }
          .tab {
            padding: 10px 20px;
            cursor: pointer;
            font-size: 13px;
            font-weight: 500;
            color: #8a8885;
            border-bottom: 2px solid transparent;
            margin-bottom: -2px;
            transition: all 0.2s;
            user-select: none;
          }
          .tab:hover { color: #4A7A23; }
          .tab.active {
            color: #4A7A23;
            border-bottom-color: #7BC043;
          }
          .tab-content { display: none; }
          .tab-content.active { display: block; }

          /* Source code */
          pre.source-code {
            margin: 0;
            padding: 16px;
            background: #ffffff;
            overflow-x: auto;
            font-size: 12px;
            line-height: 1.5;
            max-height: calc(100vh - 44px);
            overflow-y: auto;
          }
          pre.source-code code {
            background: transparent !important;
            font-family: "SF Mono", Menlo, Consolas, monospace;
          }

          /* Data preview */
          .data-preview {
            padding: 20px;
            max-height: calc(100vh - 44px);
            overflow-y: auto;
          }
          .data-section {
            margin-bottom: 32px;
          }
          .data-section h2 {
            font-size: 16px;
            font-weight: 600;
            color: #4A7A23;
            margin-bottom: 12px;
            padding-bottom: 8px;
            border-bottom: 1px solid #e0ddd8;
          }
          .data-card {
            background: #fff;
            border-radius: 10px;
            padding: 14px 18px;
            margin-bottom: 10px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.06);
            border: 1px solid #e8e6e1;
          }
          .data-card .id {
            display: inline-block;
            font-size: 11px;
            font-weight: 600;
            color: #fff;
            background: #7BC043;
            padding: 2px 8px;
            border-radius: 4px;
            margin-bottom: 6px;
          }
          .data-card .name {
            font-size: 15px;
            font-weight: 600;
            margin-bottom: 4px;
          }
          .data-card .tag {
            display: inline-block;
            font-size: 11px;
            color: #4A7A23;
            background: #eaf5e0;
            padding: 1px 8px;
            border-radius: 3px;
            margin-bottom: 6px;
          }
          .data-card .field {
            font-size: 12px;
            color: #8a8885;
            margin-top: 4px;
          }
          .data-card .field strong {
            color: #1d1d1f;
          }
          .data-card .pain {
            font-size: 13px;
            color: #c0392b;
            margin-top: 4px;
            padding-left: 8px;
            border-left: 3px solid #e74c3c;
          }
          .data-card .goal {
            font-size: 13px;
            color: #27ae60;
            margin-top: 4px;
            padding-left: 8px;
            border-left: 3px solid #2ecc71;
          }
          .empty-state {
            padding: 40px;
            text-align: center;
            color: #8a8885;
            font-size: 14px;
          }

          /* Raw JS tab */
          pre.raw-js {
            margin: 0;
            padding: 16px;
            background: #1d1d1f;
            color: #e8e6e1;
            overflow-x: auto;
            font-family: "SF Mono", Menlo, Consolas, monospace;
            font-size: 11px;
            line-height: 1.5;
            max-height: calc(100vh - 44px);
            overflow-y: auto;
          }
        </style>
        </head>
        <body>

        <div class="tabs">
          <div class="tab active" onclick="switchTab('source')">Source</div>
          <div class="tab" onclick="switchTab('preview')">Preview</div>
          <div class="tab" onclick="switchTab('compiled')">Compiled JS</div>
        </div>

        <div id="tab-source" class="tab-content active">
          <pre class="source-code"><code class="language-typescript">\(escapedSource)</code></pre>
        </div>

        <div id="tab-preview" class="tab-content">
          <div class="data-preview" id="data-preview-container">
            \(dataInitScript.html)
          </div>
        </div>

        <div id="tab-compiled" class="tab-content">
          <pre class="raw-js">\(escapeHTML(cleanJS))</pre>
        </div>

        <script>
          hljs.highlightAll();
          \(dataInitScript.js)
          function switchTab(name) {
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
            document.querySelector(`.tab[onclick*="'${name}'"]`).classList.add('active');
            document.getElementById(`tab-${name}`).classList.add('active');
            // Re-highlight when switching to source tab
            if (name === 'source') hljs.highlightAll();
          }
        </script>
        </body>
        </html>
        """
    }

    // MARK: - Data extraction & runtime rendering

    /// Extract data variables from compiled JS and return clean JS + variable names.
    private static func extractDataVariables(_ js: String) -> (cleanJS: String, varNames: [String]) {
        var clean = js
        // Strip export { ... } at the end
        let exportRange = (clean as NSString).range(of: "\nexport {", options: .backwards)
        if exportRange.location != NSNotFound {
            clean = String(clean[..<String.Index(utf16Offset: exportRange.location, in: clean)])
        }

        // Find top-level "var"/"let"/"const" declarations as potential data exports
        let regex = try! NSRegularExpression(pattern: "(?:export\\s+)?(?:var|let|const)\\s+(\\w+)", options: [])
        let nsRange = NSRange(js.startIndex..<js.endIndex, in: js)
        let matches = regex.matches(in: js, range: nsRange)
        let names = matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: js)
            else { return nil }
            return String(js[r])
        }
        // Filter out common non-data names
        let filtered = names.filter { !["exports", "module", "require", "define", "__esModule"].contains($0) }
        return (clean, filtered)
    }

    /// Builds the data initialization script for the preview tab.
    private static func buildDataInitScript(_ compiledJS: String, dataVars: [String]) -> (html: String, js: String) {
        var cleanJS = compiledJS

        // Strip ESM export statements
        let exportRegex = try! NSRegularExpression(pattern: "^export\\s+", options: .anchorsMatchLines)
        cleanJS = exportRegex.stringByReplacingMatches(in: cleanJS, range: NSRange(cleanJS.startIndex..<cleanJS.endIndex, in: cleanJS), withTemplate: "")
        let exportRange = (cleanJS as NSString).range(of: "\nexport {", options: .backwards)
        if exportRange.location != NSNotFound {
            cleanJS = String(cleanJS[..<String.Index(utf16Offset: exportRange.location, in: cleanJS)])
        }

        let js = """
        try {
          \(cleanJS)
          const dataVars = \(dataVars.isEmpty ? "[]" : "[" + dataVars.map { "\"\($0)\"" }.joined(separator: ",") + "]");
          const container = document.getElementById('data-preview-container');
          container.innerHTML = '';

          let hasData = false;
          dataVars.forEach(name => {
            const val = eval(name);
            if (!val) return;
            if (Array.isArray(val) && val.length === 0) return;

            hasData = true;
            const section = document.createElement('div');
            section.className = 'data-section';
            section.innerHTML = `<h2>${escapeHtml(name)}</h2>`;

            if (Array.isArray(val)) {
              val.forEach(item => {
                if (typeof item === 'object' && item !== null) {
                  const card = document.createElement('div');
                  card.className = 'data-card';
                  let html = '';
                  if (item.id) html += `<span class="id">${escapeHtml(item.id)}</span>`;
                  if (item.name) html += `<div class="name">${escapeHtml(item.name)}</div>`;
                  if (item.tag) html += `<span class="tag">${escapeHtml(item.tag)}</span>`;
                  if (item.title) html += `<div class="name">${escapeHtml(item.title)}</div>`;
                  if (item.core) html += `<div class="field"><strong>核心：</strong>${escapeHtml(item.core)}</div>`;
                  if (item.pain) html += `<div class="pain">😖 ${escapeHtml(item.pain)}</div>`;
                  if (item.goal) html += `<div class="goal">🎯 ${escapeHtml(item.goal)}</div>`;
                  if (item.desc) html += `<div class="field">${escapeHtml(item.desc)}</div>`;
                  // Render any remaining custom fields
                  Object.entries(item).forEach(([k, v]) => {
                    if (!['id','name','tag','title','core','pain','goal','desc','items','children'].includes(k) && typeof v !== 'object') {
                      html += `<div class="field"><strong>${escapeHtml(k)}：</strong>${escapeHtml(String(v))}</div>`;
                    }
                  });
                  // Nested items
                  if (item.items && Array.isArray(item.items)) {
                    html += '<div style="margin-top:8px;padding-left:12px;border-left:2px solid #e0ddd8;">';
                    item.items.forEach(sub => {
                      html += '<div class="data-card" style="margin-bottom:6px;">';
                      if (sub.id) html += `<span class="id">${escapeHtml(sub.id)}</span>`;
                      if (sub.name) html += `<div class="name" style="font-size:13px;">${escapeHtml(sub.name)}</div>`;
                      if (sub.tag) html += `<span class="tag">${escapeHtml(sub.tag)}</span>`;
                      if (sub.pain) html += `<div class="pain">😖 ${escapeHtml(sub.pain)}</div>`;
                      if (sub.goal) html += `<div class="goal">🎯 ${escapeHtml(sub.goal)}</div>`;
                      html += '</div>';
                    });
                    html += '</div>';
                  }
                  if (item.children && Array.isArray(item.children)) {
                    html += '<div style="margin-top:8px;padding-left:12px;border-left:2px solid #e0ddd8;">';
                    item.children.forEach(sub => {
                      html += '<div class="data-card" style="margin-bottom:6px;">';
                      if (sub.id) html += `<span class="id">${escapeHtml(sub.id)}</span>`;
                      if (sub.name) html += `<div class="name" style="font-size:13px;">${escapeHtml(sub.name)}</div>`;
                      html += '</div>';
                    });
                    html += '</div>';
                  }
                  card.innerHTML = html;
                  section.appendChild(card);
                } else {
                  const p = document.createElement('p');
                  p.textContent = String(item);
                  section.appendChild(p);
                }
              });
            } else if (typeof val === 'object') {
              const card = document.createElement('div');
              card.className = 'data-card';
              let html = '';
              if (val.title) html += `<div class="name">${escapeHtml(val.title)}</div>`;
              Object.entries(val).forEach(([k, v]) => {
                if (k !== 'title' && typeof v !== 'object') {
                  html += `<div class="field"><strong>${escapeHtml(k)}：</strong>${escapeHtml(String(v))}</div>`;
                }
              });
              card.innerHTML = html;
              section.appendChild(card);
            }

            container.appendChild(section);
          });

          if (!hasData) {
            container.innerHTML = '<div class="empty-state">该文件未导出可预览的数据。查看 Source 标签阅读源代码。</div>';
          }

          function escapeHtml(str) {
            const div = document.createElement('div');
            div.textContent = str;
            return div.innerHTML;
          }
        } catch(e) {
          document.getElementById('data-preview-container').innerHTML =
            '<div class="empty-state"><strong>预览渲染失败</strong><br><span style="color:#c0392b;font-size:13px;">' +
            escapeHtml(e.message || String(e)) + '</span><br><br>尝试查看 Source 或 Compiled JS 标签。</div>';
        }
        """

        let placeholder: String
        if dataVars.isEmpty {
            placeholder = """
            <div class="empty-state">正在准备预览数据…</div>
            """
        } else {
            placeholder = """
            <div class="empty-state">正在渲染预览…</div>
            """
        }

        return (placeholder, js)
    }

    // MARK: - Source-only fallback page

    private static func buildSourceOnlyPage(source: String, fileName: String) -> String {
        let escaped = escapeHTML(source)
        return """
        <!DOCTYPE html>
        <html lang="zh">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>\(escapeHTML(fileName))</title>
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css">
        <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body { background: #f8f7f4; padding: 16px; }
          pre {
            margin: 0;
            padding: 16px;
            background: #fff;
            border-radius: 8px;
            overflow-x: auto;
            font-size: 13px;
            line-height: 1.5;
            box-shadow: 0 1px 3px rgba(0,0,0,0.06);
          }
          code { background: transparent !important; font-family: "SF Mono", Menlo, Consolas, monospace; }
          .note {
            text-align: center;
            padding: 12px;
            color: #8a8885;
            font-size: 12px;
          }
        </style>
        </head>
        <body>
        <div class="note">esbuild 未就绪，显示源代码</div>
        <pre><code class="language-typescript">\(escaped)</code></pre>
        <script>hljs.highlightAll();</script>
        </body>
        </html>
        """
    }

    // MARK: - Error page

    private static func errorPage(_ message: String) -> String {
        return """
        <!DOCTYPE html>
        <html lang="zh">
        <head><meta charset="utf-8"><title>Error</title></head>
        <body style="font-family:sans-serif;padding:2rem;color:#c0392b;">
        <h2>⚠️ \(message)</h2>
        </body>
        </html>
        """
    }

    // MARK: - HTML escaping

    private static func escapeHTML(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#x27;")
    }
}
