import SwiftUI

/// Empty state shown inside the history scroll area.
enum HistoryEmptyContext {
    case noHistory
    case noResults(query: String)
}

struct HistoryEmptyStateView: View {

    let context: HistoryEmptyContext

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            switch context {
            case .noHistory:
                Image(systemName: "mic.badge.plus")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("Your transcriptions will appear here")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Hold Right Option to start")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            case .noResults(let query):
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("No results for")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\"\(query.prefix(24))\"")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
