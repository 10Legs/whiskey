import Foundation
import WhisKeyCore

// MARK: - Re-inject State

enum ReinjectionState: Equatable {
    case idle
    case loading
    case success
    case failure
}

// MARK: - HistoryViewModel

/// Observable view model for the history panel.
///
/// Owns fetch, filter, delete, bulk-clear, and re-inject actions.
/// `MenuBarView` pushes newly-appended entries via `appendEntry(_:)`.
@MainActor
public final class HistoryViewModel: ObservableObject {

    @Published public var entries: [HistoryEntry] = []
    @Published public var searchQuery: String = ""
    @Published public var showBulkClearConfirmation: Bool = false

    /// Per-entry re-injection state, keyed by `entry.id`.
    @Published var reinjectionStates: [String: ReinjectionState] = [:]

    /// Controls whether row action buttons are globally disabled during an in-flight injection.
    @Published var isInjecting: Bool = false

    private let historyStore: HistoryStore
    private let injector: any TextInjecting

    public init(
        historyStore: HistoryStore = HistoryStore(),
        injector: any TextInjecting = TextInjector()
    ) {
        self.historyStore = historyStore
        self.injector = injector
    }

    // MARK: - Computed

    public var filteredEntries: [HistoryEntry] {
        guard !searchQuery.isEmpty else { return entries }
        let q = searchQuery.lowercased()
        return entries.filter {
            $0.text.lowercased().contains(q) ||
            ($0.rawText?.lowercased().contains(q) ?? false)
        }
    }

    // MARK: - Fetch

    public func loadHistory() async {
        do {
            // HistoryStore is an actor; await satisfies isolation crossing.
            entries = try await historyStore.fetchRecent(limit: 500)
        } catch {
            // Degrade gracefully -- empty list is acceptable.
        }
    }

    // MARK: - Append (called by pipeline on new transcription)

    public func appendEntry(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
    }

    // MARK: - Delete

    /// Deletes the entry from the persistent store.
    ///
    /// The view layer removes the entry from `entries` optimistically before calling this
    /// (with animation). If the store delete fails the entry remains absent from the in-memory
    /// list -- acceptable for a local transcription cache.
    public func deleteEntry(_ entry: HistoryEntry) async {
        do {
            _ = try await historyStore.delete(id: entry.id)
        } catch {
            // Entry already removed from in-memory list optimistically; no recovery needed.
        }
    }

    // MARK: - Bulk Clear

    public func clearAll() async {
        do {
            try await historyStore.deleteAll()
            entries = []
        } catch {
            // No-op on failure; history remains intact.
        }
        showBulkClearConfirmation = false
    }

    // MARK: - Re-inject

    public func reinject(_ entry: HistoryEntry) async {
        guard reinjectionStates[entry.id] != .loading else { return }
        reinjectionStates[entry.id] = .loading
        isInjecting = true
        defer { isInjecting = false }

        // TextInjector.inject never throws -- failures are silent strategy fallbacks.
        await injector.inject(entry.text, capturedElement: nil)

        switch reinjectionStates[entry.id] {
        case .failure:
            try? await Task.sleep(for: .seconds(2.0))
            reinjectionStates[entry.id] = .idle
        default:
            reinjectionStates[entry.id] = .success
            try? await Task.sleep(for: .seconds(1.2))
            reinjectionStates[entry.id] = .idle
        }
    }
}

