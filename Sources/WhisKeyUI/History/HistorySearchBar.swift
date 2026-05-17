import SwiftUI

/// Pinned search bar at the top of `HistoryView`.
///
/// Does not scroll away. Filters are applied synchronously in `HistoryViewModel.filteredEntries`.
struct HistorySearchBar: View {

    @Binding var query: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            TextField("", text: $query, prompt: Text("Search transcriptions").foregroundStyle(.tertiary))
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .accessibilityLabel("Search transcriptions")

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
        )
    }
}
