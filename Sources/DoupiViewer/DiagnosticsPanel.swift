import SwiftUI

/// Error panel displayed when preview build fails.
/// Shows categorized diagnostics with icon, title, and detail list.
struct DiagnosticsPanel: View {

    let title: String
    let icon: String
    let iconColor: Color
    let diagnostics: [PreviewDiagnostic]

    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(iconColor)

                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundColor(.appText)

                Text(errorSummary)
                    .font(.appBody)
                    .foregroundColor(.appMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 32)

            // Diagnostics list
            if !diagnostics.isEmpty {
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(diagnostics) { diag in
                            diagnosticRow(diag)
                        }
                    }
                    .padding(12)
                }
                .background(Color(hex: "#1e1e1e"))
                .cornerRadius(8)
                .padding(.horizontal, 24)
                .frame(maxHeight: 300)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    // MARK: - Helpers

    private var errorSummary: String {
        let errors = diagnostics.filter { $0.level == .error }.count
        let warnings = diagnostics.filter { $0.level == .warning }.count
        var parts: [String] = []
        if errors > 0 { parts.append("\(errors) 个错误") }
        if warnings > 0 { parts.append("\(warnings) 个警告") }
        return parts.isEmpty ? "无详细信息" : parts.joined(separator: "，")
    }

    @ViewBuilder
    private func diagnosticRow(_ diag: PreviewDiagnostic) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconForLevel(diag.level))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colorForLevel(diag.level))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(diag.message)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(Color(hex: "#d4d4d4"))
                    .textSelection(.enabled)

                if let file = diag.file {
                    let loc = diag.line.map { ":\($0)" } ?? ""
                    Text("\(URL(fileURLWithPath: file).lastPathComponent)\(loc)")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(Color(hex: "#808080"))
                }
            }
        }
    }

    private func iconForLevel(_ level: PreviewDiagnostic.Level) -> String {
        switch level {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func colorForLevel(_ level: PreviewDiagnostic.Level) -> Color {
        switch level {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}

// MARK: - Convenience initializers for the three error categories

extension DiagnosticsPanel {
    static func runtimeError(message: String, checkedPaths: [String] = []) -> DiagnosticsPanel {
        var diags = [PreviewDiagnostic(level: .error, message: message, file: nil, line: nil)]
        for path in checkedPaths {
            diags.append(PreviewDiagnostic(level: .info, message: "检查过: \(path)", file: nil, line: nil))
        }
        return DiagnosticsPanel(
            title: "esbuild 运行时错误",
            icon: "exclamationmark.triangle.fill",
            iconColor: .orange,
            diagnostics: diags
        )
    }

    static func buildError(diagnostics: [PreviewDiagnostic]) -> DiagnosticsPanel {
        DiagnosticsPanel(
            title: "TSX 构建失败",
            icon: "xmark.octagon.fill",
            iconColor: .red,
            diagnostics: diagnostics
        )
    }

    static func webRuntimeError(message: String) -> DiagnosticsPanel {
        DiagnosticsPanel(
            title: "WebView 加载错误",
            icon: "globe.badge.exclamationmark",
            iconColor: .purple,
            diagnostics: [PreviewDiagnostic(level: .error, message: message, file: nil, line: nil)]
        )
    }
}
