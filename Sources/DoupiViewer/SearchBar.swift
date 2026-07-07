import SwiftUI

/// Search bar overlay shown at the top of the document area when ⌘+F is pressed.
struct SearchBar: View {

    @Binding var query: String
    let matchCount: Int
    let currentMatch: Int
    let onNext: () -> Void
    let onPrev: () -> Void
    let onClose: () -> Void

    @FocusState private var isFocused: Bool
    @State private var localQuery: String = ""

    var body: some View {
        HStack(spacing: 8) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.appMuted)

            // Text field
            TextField("搜索...", text: $localQuery)
                .textFieldStyle(.plain)
                .font(.appBody)
                .foregroundColor(.appText)
                .focused($isFocused)
                .onChange(of: localQuery) { _, newValue in
                    query = newValue
                }
                .onSubmit { onNext() }

            // Match count
            if !query.isEmpty {
                Text(matchText)
                    .font(.appSmall)
                    .foregroundColor(.appMuted)
                    .monospacedDigit()
            }

            // Navigation buttons
            HStack(spacing: 2) {
                Button(action: onPrev) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .disabled(matchCount == 0)

                Button(action: onNext) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .disabled(matchCount == 0)
            }
            .foregroundColor(.appMuted)

            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.appMuted)
            }
            .buttonStyle(.plain)
            .help("关闭搜索 (Esc)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.appInfoBg)
        .cornerRadius(8)
        .onAppear {
            localQuery = query
            isFocused = true
        }
    }

    private var matchText: String {
        if matchCount == 0 { return "0/0" }
        let cur = min(currentMatch + 1, matchCount)
        return "\(cur)/\(matchCount)"
    }
}
