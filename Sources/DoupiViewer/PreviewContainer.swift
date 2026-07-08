import SwiftUI

/// Drives the full TSX/JSX preview lifecycle using PreviewState.
/// Renders different views for each state: loading spinner, diagnostics panel, or the built WebView.
struct PreviewContainer: View {

    let sourceURL: URL

    /// Search support propagated to inner WebView.
    var searchQuery: String? = nil
    var searchAction: SearchAction? = nil

    /// Called when search results update: (matchCount, currentMatch).
    var onSearchUpdate: ((Int, Int) -> Void)? = nil

    @State private var state: PreviewState = .idle
    @State private var esbuildPath: String?
    @State private var webError: String?

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            switch state {
            case .idle, .resolvingRuntime, .preparingWorkspace, .building:
                loadingView

            case .buildSucceeded(let indexHTMLURL):
                previewWebView(indexHTMLURL: indexHTMLURL)

            case .buildFailed(let diagnostics):
                DiagnosticsPanel.buildError(diagnostics: diagnostics)

            case .loadingWebView:
                loadingView

            case .ready:
                loadingView
            }

            // Show web runtime error overlay if WebView reports an error
            if let err = webError, state.isLoading == false {
                DiagnosticsPanel.webRuntimeError(message: err)
                    .transition(.opacity)
            }
        }
        .task(id: sourceURL) {
            await runPreviewPipeline()
        }
        .onChange(of: sourceURL) { _, _ in
            state = .idle
            webError = nil
        }
    }

    // MARK: - Loading view

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(stateMessage)
                .font(.appBody)
                .foregroundColor(.appMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stateMessage: String {
        switch state {
        case .idle: return "初始化..."
        case .resolvingRuntime: return "检查 esbuild..."
        case .preparingWorkspace: return "准备工作区..."
        case .building: return "编译 TSX..."
        case .loadingWebView: return "加载预览..."
        default: return "处理中..."
        }
    }

    // MARK: - Preview WebView

    private func previewWebView(indexHTMLURL: URL) -> some View {
        let workspaceURL = indexHTMLURL.deletingLastPathComponent()
        return WebView(
            fileURL: indexHTMLURL,
            readAccessRoot: workspaceURL,
            searchQuery: searchQuery,
            searchAction: searchAction,
            onNavigationError: { err in
                webError = err
            },
            onSearchUpdate: onSearchUpdate
        )
    }

    // MARK: - Pipeline

    private func runPreviewPipeline() async {
        // Step 1: Resolve esbuild (on global queue — Process.waitUntilExit blocks)
        await MainActor.run { state = .resolvingRuntime }

        let resolved = await Task.detached(priority: .userInitiated) {
            EsbuildManager.resolve()
        }.value
        switch resolved {
        case .ready(let path, let version):
            fputs("[PreviewContainer] esbuild ready: \(path) (\(version))\n", stderr)
            esbuildPath = path

        case .notFound(let paths):
            fputs("[PreviewContainer] esbuild not found\n", stderr)
            await MainActor.run {
                state = .buildFailed([PreviewDiagnostic(
                    level: .error,
                    message: "esbuild 未找到，无法编译 TSX。请安装 esbuild：\nnpm install -g esbuild",
                    file: nil, line: nil
                )] + paths.map { path in
                    PreviewDiagnostic(level: .info, message: "检查过: \(path)", file: nil, line: nil)
                })
            }
            return
        }

        // Step 2: Build (on global queue — Process.waitUntilExit blocks)
        await MainActor.run { state = .building }

        guard let esbuildPath = esbuildPath else { return }

        let result = await Task.detached(priority: .userInitiated) {
            PreviewCompiler.compile(sourceURL: sourceURL, esbuildPath: esbuildPath)
        }.value

        switch result {
        case .success(let indexHTMLURL):
            fputs("[PreviewContainer] build succeeded \(indexHTMLURL.path)\n", stderr)
            await MainActor.run {
                // Atomsically transition: show succeeded state with no intermediate loadingWebView flash.
                state = .buildSucceeded(indexHTMLURL)
            }

        case .failure(let buildError):
            fputs("[PreviewContainer] build failed with \(buildError.diagnostics.count) diagnostics\n", stderr)
            await MainActor.run {
                state = .buildFailed(buildError.diagnostics)
            }
        }
    }
}
