import SwiftUI
import WhisKeyCore

/// Full history panel — search, scrollable list, bulk-clear confirmation.
///
/// Replaces the old `historyList` section in `MenuBarView`.
public struct HistoryView: View {

    @ObservedObject var viewModel: HistoryViewModel
    /// Closure that triggers bulk-clear confirmation banner from the footer trash button.
    let onBulkClearRequested: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        VStack(spacing: 0) {
            // Pinned search bar
            HistorySearchBar(query: $viewModel.searchQuery)
                .padding(.bottom, 8)

            // Scrollable entry list
            ScrollView {
                LazyVStack(spacing: 6) {
                    if viewModel.filteredEntries.isEmpty {
                        emptyState
                            .frame(minHeight: 200)
                    } else {
                        ForEach(viewModel.filteredEntries) { entry in
                            HistoryRowView(
                                entry: entry,
                                reinjectionState: viewModel.reinjectionStates[entry.id] ?? .idle,
                                actionsDisabled: viewModel.isInjecting,
                                onReinject: { await viewModel.reinject(entry) },
                                onCancelReinject: { viewModel.cancelReinject(entry) },
                                onDelete: {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                        viewModel.entries.removeAll { $0.id == entry.id }
                                    }
                                    await viewModel.deleteEntry(entry)
                                }
                            )
                            .transition(
                                reduceMotion
                                    ? .identity
                                    : .move(edge: .trailing).combined(with: .opacity)
                            )
                        }
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.filteredEntries.map(\.id))
                .padding(.bottom, 4)
            }

            // Inline bulk-clear confirmation banner
            if viewModel.showBulkClearConfirmation {
                bulkClearBanner
                    .transition(
                        reduceMotion
                            ? .identity
                            : .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            )
                    )
            }
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.searchQuery.isEmpty {
            HistoryEmptyStateView(context: .noHistory)
        } else {
            HistoryEmptyStateView(context: .noResults(query: viewModel.searchQuery))
        }
    }

    // MARK: - Bulk-clear confirmation banner

    private var bulkClearBanner: some View {
        HStack {
            Text("Clear all \(viewModel.entries.count) entries?")
                .font(.system(size: 12))
                .foregroundStyle(.primary)

            Spacer()

            Button("Cancel") {
                withAnimation(reduceMotion ? nil : .spring(response: 0.25)) {
                    viewModel.showBulkClearConfirmation = false
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))

            Button("Clear All", role: .destructive) {
                Task {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.25)) {
                        viewModel.showBulkClearConfirmation = false
                    }
                    await viewModel.clearAll()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.red)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        )
        .padding(.top, 6)
        .task {
            // Auto-dismiss after 6 s if the user takes no action.
            try? await Task.sleep(for: .seconds(6))
            withAnimation(reduceMotion ? nil : .spring(response: 0.25)) {
                viewModel.showBulkClearConfirmation = false
            }
        }
    }
}
