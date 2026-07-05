import SwiftUI

/// Drives the full TSX/JSX preview lifecycle using PreviewState.
/// Renders different views for each state: loading spinner, diagnostics panel, or the built WebView.
struct PreviewContainer: View {

    let sourceURL: URL

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
                // Should not reach here in normal flow
                loadingView
            }

            // Show web runtime error overlay if WebView reports an error
            if let err = webError, state.isLoading == false {
                DiagnosticsPanel.webRuntimeError(message: err)
                    .transition(.opacity)
            }
        }
        .task {
            await runPreviewPipeline()
        }
        .onChange(of: webError) { _, newErr in
            if newErr != nil {
                // If WebView reports error after successful build, update state
                // but don't override buildSucceeded — the overlay handles display
            }
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
        // Use loadHTMLString with baseURL so ES module CDN imports (https://esm.sh) work.
        // loadFileURL would block cross-origin ES module imports from file:// protocol.
        let htmlContent = (try? String(contentsOf: indexHTMLURL, encoding: .utf8)) ?? "<h3>无法加载预览</h3>"
        return WebView(
            htmlString: htmlContent,
            baseURL: workspaceURL,
            onNavigationError: { err in
                webError = err
            }
        )
        .onChange(of: webError) { _, newErr in
            if newErr != nil {
                // Transition to show web runtime error
            }
        }
    }

    // MARK: - Pipeline

    private func runPreviewPipeline() async {
        // Step 1: Resolve esbuild (dispatch to background thread explicitly)
        await MainActor.run { state = .resolvingRuntime }
        
        let resolved: EsbuildManager.ResolveResult = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: EsbuildManager.resolve())
            }
        }
        switch resolved {
        case .ready(let path, let version):
            fputs("[PreviewContainer] esbuild ready: \(path) (\(version))\n", stderr)
            await MainActor.run { esbuildPath = path }
        
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
        
        // Step 2 & 3: Prepare workspace + Build (dispatch to background thread explicitly)
        await MainActor.run { state = .building }
        
        let currentEsbuildPath = await MainActor.run { esbuildPath }
        guard let esbuildPath = currentEsbuildPath else { return }
        
        let result: Result<URL, PreviewBuildError> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: PreviewCompiler.compile(sourceURL: self.sourceURL, esbuildPath: esbuildPath))
            }
        }
        
        switch result {
        case .success(let indexHTMLURL):
            fputs("[PreviewContainer] build succeeded \(indexHTMLURL.path)\n", stderr)
            await MainActor.run { state = .loadingWebView }
        
            // Small delay to let SwiftUI transition to loadingWebView
            try? await Task.sleep(for: .milliseconds(50))
            await MainActor.run {
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
