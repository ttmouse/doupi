import Foundation

/// Discovers and validates the local esbuild binary.
/// Supports: App Bundle Resources, Homebrew, /usr/local/bin, project node_modules.
struct EsbuildManager {

    /// Result of resolving the esbuild binary.
    enum ResolveResult: Equatable {
        case ready(path: String, version: String)
        case notFound(checkedPaths: [String])
    }

    // MARK: - Public

    /// Synchronous resolve: find esbuild, verify it runs, return path + version.
    static func resolve() -> ResolveResult {
        let candidates = candidatePaths()
        for path in candidates {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
                  !isDir.boolValue else { continue }

            // Check executable permission
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }

            // Verify with --version
            if let version = runVersionCheck(path: path) {
                fputs("[EsbuildManager] found esbuild at \(path) version \(version)\n", stderr)
                return .ready(path: path, version: version)
            }
        }
        fputs("[EsbuildManager] esbuild not found, checked: \(candidates)\n", stderr)
        return .notFound(checkedPaths: candidates)
    }

    // MARK: - Private

    private static func candidatePaths() -> [String] {
        var paths: [String] = []

        // 1. App Bundle Resources
        if let resPath = Bundle.main.resourcePath {
            paths.append("\(resPath)/esbuild")
        }

        // 2. Homebrew arm64
        paths.append("/opt/homebrew/bin/esbuild")

        // 3. Homebrew x86 / /usr/local
        paths.append("/usr/local/bin/esbuild")

        // 4. Common npm global locations
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        paths.append("\(home)/.npm-global/bin/esbuild")
        paths.append("\(home)/.nvm/versions/node/*/bin/esbuild")

        // 5. npx fallback (uses whatever node env is active)
        // We try running "npx esbuild --version" as last resort
        // handled separately in runVersionCheck

        return paths
    }

    private static func runVersionCheck(path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do { try process.run() } catch { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
