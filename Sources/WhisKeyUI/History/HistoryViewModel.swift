import AppKit
import Foundation
import WhisKeyCore

// MARK: - Re-inject State

enum ReinjectionState: Equatable {
    case idle
    /// Countdown in progress; `seconds` is the remaining count (3 → 2 → 1).
    case countdown(seconds: Int)
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
    /// Called when a re-injection is blocked due to a sensitive target.
    /// The caller (MenuBarView) wires this to `PipelineStateModel.postError`.
    var onError: ((String) -> Void)?

    public init(
        historyStore: HistoryStore = HistoryStore(),
        injector: any TextInjecting = TextInjector(),
        onError: ((String) -> Void)? = nil
    ) {
        self.historyStore = historyStore
        self.injector = injector
        self.onError = onError
    }

    // MARK: - Computed

    public var filteredEntries: [HistoryEntry] {
        guard !searchQuery.isEmpty else { return entries }
        let query = searchQuery.lowercased()
        return entries.filter {
            $0.text.lowercased().contains(query) ||
            ($0.rawText?.lowercased().contains(query) ?? false)
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
        // Ignore taps while already active for this entry.
        switch reinjectionStates[entry.id] {
        case .countdown, .loading:
            return
        default:
            break
        }

        // --- Countdown phase (3 → 2 → 1) ---
        // The row UI shows "Cancel (N)" during this window.
        // Tapping cancel sets the state to .idle, which breaks the loop.
        for remaining in stride(from: 3, through: 1, by: -1) {
            reinjectionStates[entry.id] = .countdown(seconds: remaining)
            try? await Task.sleep(for: .seconds(1))

            // Cancelled by user or superseded externally.
            guard case .countdown = reinjectionStates[entry.id] else { return }
        }

        // --- Sensitivity guard ---
        // Read the currently focused application at the moment of injection,
        // not at button-tap time.  Clicking history steals focus so we query
        // NSWorkspace for the frontmost app at fire time.
        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if SensitiveAppRegistry.isSensitive(frontBundleID) {
            reinjectionStates[entry.id] = .failure
            onError?("Re-injection blocked: sensitive target detected.")
            try? await Task.sleep(for: .seconds(2.0))
            reinjectionStates[entry.id] = .idle
            return
        }

        // --- Injection phase ---
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

    // MARK: - Countdown Cancel

    /// Cancels an in-progress countdown for the given entry, aborting the
    /// pending re-injection.
    public func cancelReinject(_ entry: HistoryEntry) {
        guard case .countdown = reinjectionStates[entry.id] else { return }
        reinjectionStates[entry.id] = .idle
    }
}
