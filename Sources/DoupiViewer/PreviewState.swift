import Foundation

// MARK: - Preview State Machine

/// Drives the TSX/JSX preview lifecycle: idle → resolving → preparing → building → (succeeded|failed) → loading → ready
enum PreviewState: Equatable {
    case idle
    case resolvingRuntime
    case preparingWorkspace
    case building
    case buildSucceeded(URL)          // index.html URL
    case buildFailed([PreviewDiagnostic])
    case loadingWebView
    case ready

    var isActive: Bool {
        switch self {
        case .idle: return false
        default: return true
        }
    }

    var isLoading: Bool {
        switch self {
        case .resolvingRuntime, .preparingWorkspace, .building, .loadingWebView:
            return true
        default:
            return false
        }
    }

    var diagnostics: [PreviewDiagnostic] {
        if case .buildFailed(let d) = self { return d }
        return []
    }
}

// MARK: - Error Types

/// Three distinct error categories per the architecture spec.
enum PreviewError: Error, LocalizedError, Equatable {
    case runtime(RuntimeError)
    case build(BuildError)
    case webRuntime(WebRuntimeError)

    var errorDescription: String? {
        switch self {
        case .runtime(let e): return e.message
        case .build(let e): return e.message
        case .webRuntime(let e): return e.message
        }
    }
}

struct RuntimeError: Error, LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

struct BuildError: Error, LocalizedError, Equatable {
    let message: String
    let stderr: String
    let stdout: String
    var errorDescription: String? { message }
}

struct WebRuntimeError: Error, LocalizedError, Equatable {
    let message: String
    let failingURL: String?
    var errorDescription: String? { message }
}

// MARK: - Build Failure Wrapper (for Result<Success, Failure>)

/// Wraps diagnostics in an Error-conforming type for use with Result.
struct PreviewBuildError: Error, Equatable {
    let diagnostics: [PreviewDiagnostic]
}

// MARK: - Diagnostics

/// A single diagnostic item for the error panel.
struct PreviewDiagnostic: Identifiable, Equatable {
    let id = UUID()
    let level: Level
    let message: String
    let file: String?
    let line: Int?

    enum Level: String {
        case error
        case warning
        case info
    }
}
