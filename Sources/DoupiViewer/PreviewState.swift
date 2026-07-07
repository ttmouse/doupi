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
