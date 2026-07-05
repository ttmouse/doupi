import Foundation

/// Orchestrates the full TSX preview pipeline:
///   source.tsx -> workspace -> preview-entry.tsx -> esbuild -> bundle.js -> index.html
///
/// Two-phase build strategy:
///   Phase 1: Full `--bundle` (works when react etc. are in node_modules)
///   Phase 2: Fallback `--bundle --external:react --external:react-dom` + CDN rewriting
///            (works for standalone TSX files without local dependencies)
struct PreviewCompiler {

    // MARK: - Cache directory

    // Use temp directory to avoid com.apple.provenance issues in ~/Library/Caches/
    private static let cacheBase: URL = {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LocalWebPreview/builds", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        return temp
    }()

    private static var fm: FileManager { FileManager.default }

    // MARK: - External packages for CDN fallback

    private static let externalPackages = [
        "react", "react-dom", "react-dom/client",
        "react/jsx-runtime", "react/jsx-dev-runtime",
        "lucide-react",
    ]

    // MARK: - CDN rewrite table

    private static let cdnRewrites: [(from: String, to: String)] = [
        ("from \"react\"",                  "from \"https://esm.sh/react@19\""),
        ("from 'react'",                   "from 'https://esm.sh/react@19'"),
        ("from \"react/jsx-runtime\"",     "from \"https://esm.sh/react@19/jsx-runtime\""),
        ("from 'react/jsx-runtime'",       "from 'https://esm.sh/react@19/jsx-runtime'"),
        ("from \"react/jsx-dev-runtime\"", "from \"https://esm.sh/react@19/jsx-dev-runtime\""),
        ("from 'react/jsx-dev-runtime'",   "from 'https://esm.sh/react@19/jsx-dev-runtime'"),
        ("from \"react-dom/client\"",      "from \"https://esm.sh/react-dom@19/client\""),
        ("from 'react-dom/client'",        "from 'https://esm.sh/react-dom@19/client'"),
        ("from \"lucide-react\"",          "from \"https://esm.sh/lucide-react@0.400\""),
        ("from 'lucide-react'",            "from 'https://esm.sh/lucide-react@0.400'"),
    ]

    // MARK: - Public API

    /// Compile a TSX/JSX file. Returns index.html URL on success, or diagnostics on failure.
    static func compile(sourceURL: URL, esbuildPath: String) -> Result<URL, PreviewBuildError> {
        // Use UUID to avoid conflicts with old workspace directories
        let workspace = cacheBase.appendingPathComponent(UUID().uuidString, isDirectory: true)

        // 1. Prepare workspace — copy source into workspace so esbuild can read it
        let prepResult = prepareWorkspace(source: sourceURL, workspace: workspace)
        if case .failure(let err) = prepResult { return .failure(err) }

        // 2. Run esbuild (two-phase)
        let buildResult = runEsbuild(workspace: workspace, esbuildPath: esbuildPath)
        if case .failure(let err) = buildResult { return .failure(err) }

        // 3. Generate index.html with inlined bundle + tailwind
        let indexHTML = workspace.appendingPathComponent("index.html")
        let bundleURL = workspace.appendingPathComponent("bundle.js")
        guard let bundleData = fm.contents(atPath: bundleURL.path),
              let bundleContent = String(data: bundleData, encoding: .utf8) else {
            return .failure(PreviewBuildError(diagnostics: [PreviewDiagnostic(
                level: .error,
                message: "Cannot read bundle.js for inlining",
                file: bundleURL.path, line: nil
            )]))
        }
        let tailwindJS = loadTailwindRuntime()
        let html = previewHTMLTemplate(bundleContent: bundleContent, tailwindJS: tailwindJS)
        do {
            try html.write(to: indexHTML, atomically: true, encoding: .utf8)
        } catch {
            return .failure(PreviewBuildError(diagnostics: [PreviewDiagnostic(
                level: .error,
                message: "Failed to write index.html: \(error.localizedDescription)",
                file: indexHTML.path, line: nil
            )]))
        }

        fputs("[PreviewCompiler] build succeeded \(indexHTML.path)\n", stderr)
        return .success(indexHTML)
    }

    // MARK: - Step 1: Prepare workspace

    private static func prepareWorkspace(source: URL, workspace: URL) -> Result<Void, PreviewBuildError> {
        do {
            try fm.createDirectory(at: workspace, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: workspace.path)
        } catch {
            return .failure(PreviewBuildError(diagnostics: [PreviewDiagnostic(
                level: .error,
                message: "Cannot create workspace: \(error.localizedDescription)",
                file: workspace.path, line: nil
            )]))
        }

        // Copy source file in-process so macOS user-selected file access applies
        // before esbuild runs from the temporary workspace.
        let ext = source.pathExtension.lowercased()
        let dest = workspace.appendingPathComponent("source.\(ext)")
        fputs("[PreviewCompiler] copying \(source.path) -> \(dest.path)\n", stderr)
        let accessGranted = source.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                source.stopAccessingSecurityScopedResource()
            }
        }

        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            let data = try Data(contentsOf: source, options: [.mappedIfSafe])
            try data.write(to: dest, options: [.atomic])
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dest.path)
        } catch {
            return .failure(PreviewBuildError(diagnostics: [PreviewDiagnostic(
                level: .error,
                message: "Cannot copy source file: \(error.localizedDescription)",
                file: source.path, line: nil
            )]))
        }

        // Verify the copy succeeded
        guard fm.fileExists(atPath: dest.path) else {
            return .failure(PreviewBuildError(diagnostics: [PreviewDiagnostic(
                level: .error,
                message: "Cannot copy source file: copied file not found",
                file: source.path, line: nil
            )]))
        }

        // Symlink nearest node_modules into workspace so esbuild can bundle
        // react, react-dom, etc. without falling back to CDN imports (which
        // WKWebView blocks from file:// origins due to CORS).
        let nmResult = linkNodeModules(source: source, workspace: workspace)
        if case .failure(let err) = nmResult { return .failure(err) }

        // Generate preview-entry.tsx
        let entry = previewEntryTSX(ext: ext)
        do {
            try entry.write(to: workspace.appendingPathComponent("preview-entry.tsx"),
                             atomically: true, encoding: .utf8)
        } catch {
            return .failure(PreviewBuildError(diagnostics: [PreviewDiagnostic(
                level: .error,
                message: "Cannot write preview-entry.tsx: \(error.localizedDescription)",
                file: nil, line: nil
            )]))
        }

        return .success(())
    }

    // MARK: - node_modules resolution

    /// Walk up from `source` looking for a `node_modules` directory
    /// that actually contains `react` (not just random packages).
    /// If found, symlink it into the workspace so esbuild Phase 1 can bundle deps.
    private static func linkNodeModules(source: URL, workspace: URL) -> Result<Void, PreviewBuildError> {
        let candidates = resolveNodeModulesPaths(source: source)
        for nmPath in candidates {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: nmPath, isDirectory: &isDir), isDir.boolValue else { continue }

            // Verify it has react — otherwise esbuild will still fail Phase 1
            let reactPkg = nmPath + "/react/package.json"
            guard fm.fileExists(atPath: reactPkg) else {
                fputs("[PreviewCompiler] skipping \(nmPath) (no react)\n", stderr)
                continue
            }

            let linkDest = workspace.appendingPathComponent("node_modules")
            do {
                try fm.createSymbolicLink(at: linkDest, withDestinationURL: URL(fileURLWithPath: nmPath))
                fputs("[PreviewCompiler] linked node_modules \(nmPath) -> \(linkDest.path)\n", stderr)
                return .success(())
            } catch {
                fputs("[PreviewCompiler] symlink node_modules failed: \(error.localizedDescription)\n", stderr)
                // Fall through to next candidate
            }
        }
        // Not finding node_modules is not fatal — Phase 2 CDN fallback will kick in
        fputs("[PreviewCompiler] no node_modules found, will rely on CDN fallback\n", stderr)
        return .success(())
    }

    /// Build ordered list of possible node_modules paths.
    private static func resolveNodeModulesPaths(source: URL) -> [String] {
        var paths: [String] = []

        // 1. Walk up from source file's directory
        var current = source.deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = current.appendingPathComponent("node_modules").path
            paths.append(candidate)
            let parent = current.deletingLastPathComponent()
            if parent == current { break }
            current = parent
        }

        // 2. App project root (development builds)
        if let resPath = Bundle.main.resourcePath {
            // In dev: Sources/DoupiViewer/Resources -> project root is 3 levels up
            let projRoot = URL(fileURLWithPath: resPath)
                .deletingLastPathComponent()  // Resources
                .deletingLastPathComponent()  // DoupiViewer
                .deletingLastPathComponent()  // Sources
            paths.append(projRoot.appendingPathComponent("node_modules").path)
        }

        // 3. Hard-coded project path (production fallback)
        let home = fm.homeDirectoryForCurrentUser.path
        paths.append("\(home)/Projects/doupi/node_modules")

        return paths
    }

    // MARK: - Step 2: esbuild (two-phase)

    private static func runEsbuild(workspace: URL, esbuildPath: String) -> Result<Void, PreviewBuildError> {
        // Phase 1: Full bundle (works when dependencies are in node_modules)
        let primaryResult = executeEsbuild(
            workspace: workspace, esbuildPath: esbuildPath, extraArgs: []
        )

        if case .success = primaryResult {
            return .success(())
        }

        // Phase 2: Fallback with external packages + CDN rewriting
        fputs("[PreviewCompiler] primary bundle failed, trying CDN fallback\n", stderr)
        let fallbackResult = executeEsbuild(
            workspace: workspace, esbuildPath: esbuildPath,
            extraArgs: externalPackages.flatMap { ["--external:\($0)"] }
        )

        switch fallbackResult {
        case .success:
            // Rewrite the bundle to use CDN URLs
            let bundleURL = workspace.appendingPathComponent("bundle.js")
            if let data = fm.contents(atPath: bundleURL.path),
               var js = String(data: data, encoding: .utf8) {
                for (from, to) in cdnRewrites {
                    js = js.replacingOccurrences(of: from, with: to)
                }
                try? js.write(to: bundleURL, atomically: true, encoding: .utf8)
                fputs("[PreviewCompiler] CDN rewrite done, bundle now uses esm.sh imports\n", stderr)
            }
            return .success(())

        case .failure(let err):
            // Both phases failed — return the primary error (more informative)
            return .failure(err)
        }
    }

    /// Execute esbuild with given arguments. Returns success or failure with diagnostics.
    private static func executeEsbuild(workspace: URL, esbuildPath: String, extraArgs: [String]) -> Result<Void, PreviewBuildError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: esbuildPath)
        process.arguments = [
            "preview-entry.tsx",
            "--bundle",
            "--outfile=bundle.js",
            "--format=esm",
            "--platform=browser",
            "--loader:.ts=ts",
            "--loader:.tsx=tsx",
            "--loader:.js=js",
            "--loader:.jsx=jsx",
            "--loader:.css=css",
            "--loader:.png=file",
            "--loader:.jpg=file",
            "--loader:.jpeg=file",
            "--loader:.svg=file",
            "--sourcemap=inline",
            "--jsx=automatic",
            "--define:process.env.NODE_ENV=\"development\"",
            "--log-level=info",
        ] + extraArgs
        process.currentDirectoryURL = workspace

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return .failure(PreviewBuildError(diagnostics: [PreviewDiagnostic(
                level: .error,
                message: "Failed to launch esbuild: \(error.localizedDescription)",
                file: esbuildPath, line: nil
            )]))
        }

        // Read pipes BEFORE waitUntilExit to avoid deadlock when output exceeds 64KB buffer
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        _ = String(data: outData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            fputs("[PreviewCompiler] esbuild failed (status \(process.terminationStatus))\n", stderr)
            fputs("[PreviewCompiler] stderr: \(errStr)\n", stderr)

            let diagnostics = parseEsbuildErrors(stderr: errStr, source: workspace)
            return .failure(PreviewBuildError(diagnostics: diagnostics.isEmpty ? [PreviewDiagnostic(
                level: .error,
                message: "esbuild failed with exit code \(process.terminationStatus)",
                file: nil, line: nil
            )] : diagnostics))
        }

        // Verify bundle.js was created
        let bundle = workspace.appendingPathComponent("bundle.js")
        guard fm.fileExists(atPath: bundle.path) else {
            return .failure(PreviewBuildError(diagnostics: [PreviewDiagnostic(
                level: .error,
                message: "esbuild succeeded but bundle.js was not created",
                file: bundle.path, line: nil
            )]))
        }

        return .success(())
    }

    // MARK: - Step 3: HTML template

    /// Inline bundle and Tailwind runtime into HTML so file:// protocol
    /// doesn't block CDN imports or external scripts.
    private static func previewHTMLTemplate(bundleContent: String, tailwindJS: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>Preview</title>
          <script>\(tailwindJS)</script>
          <style>
            html, body, #root {
              margin: 0;
              width: 100%;
              min-height: 100%;
            }
          </style>
        </head>
        <body>
          <div id="root"></div>
          <script type="module">
        \(bundleContent)
          </script>
        </body>
        </html>
        """
    }

    /// Read Tailwind CSS runtime from app bundle resources.
    /// Falls back to empty string if the resource is unavailable.
    private static func loadTailwindRuntime() -> String {
        guard let resPath = Bundle.main.resourcePath else {
            fputs("[PreviewCompiler] no resource path, tailwind unavailable\n", stderr)
            return ""
        }
        let jsURL = URL(fileURLWithPath: resPath).appendingPathComponent("tailwind-cdn.js")
        guard let data = try? Data(contentsOf: jsURL),
              let js = String(data: data, encoding: .utf8) else {
            fputs("[PreviewCompiler] cannot read tailwind-cdn.js from bundle\n", stderr)
            return ""
        }
        return js
    }

    // MARK: - Preview entry template

    private static func previewEntryTSX(ext: String) -> String {
        """
        import React from "react";
        import { createRoot } from "react-dom/client";
        import Component from "./source.\(ext)";

        createRoot(document.getElementById("root")!).render(<Component />);
        """
    }

    // MARK: - esbuild error parsing

    private static func parseEsbuildErrors(stderr: String, source: URL) -> [PreviewDiagnostic] {
        var diagnostics: [PreviewDiagnostic] = []
        let lines = stderr.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let level: PreviewDiagnostic.Level = trimmed.hasPrefix("error") || trimmed.contains(": error:") ? .error : .warning

            var file: String? = nil
            var lineNum: Int? = nil

            // Pattern: "source.tsx:5:3: error: ..."
            if let range = trimmed.range(of: #"(\S+\.tsx?):(\d+):(\d+):"#, options: .regularExpression) {
                let match = String(trimmed[range])
                let parts = match.split(separator: ":")
                if parts.count >= 2 {
                    file = source.appendingPathComponent(String(parts[0])).path
                    lineNum = Int(parts[1])
                }
            }

            diagnostics.append(PreviewDiagnostic(
                level: level,
                message: trimmed,
                file: file,
                line: lineNum
            ))
        }

        if diagnostics.isEmpty && !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append(PreviewDiagnostic(
                level: .error,
                message: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                file: nil, line: nil
            ))
        }

        return diagnostics
    }
}
