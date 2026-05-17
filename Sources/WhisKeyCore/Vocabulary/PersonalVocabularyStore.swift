import Foundation

// MARK: - PersonalVocabularyError

/// Errors thrown by `PersonalVocabularyStore`.
public enum PersonalVocabularyError: Error, LocalizedError {
    /// The term is empty (or whitespace-only) after trimming.
    case emptyTerm
    /// Adding this term would exceed the maximum allowed count.
    case tooManyTerms(max: Int)
    /// A case-insensitive duplicate of the term already exists.
    case duplicateTerm(existing: String)

    public var errorDescription: String? {
        switch self {
        case .emptyTerm:
            return "Vocabulary terms cannot be empty."
        case .tooManyTerms(let max):
            return "You can store at most \(max) vocabulary terms."
        case .duplicateTerm(let existing):
            return "\"\(existing)\" is already in your vocabulary."
        }
    }
}

// MARK: - PersonalVocabularyStore

/// Persists user-supplied vocabulary terms to `UserDefaults`.
///
/// Terms are injected into the Whisper `initial_prompt` parameter to bias
/// beam-search toward proper nouns, product names, and other domain-specific
/// words that Whisper frequently mis-transcribes.
///
/// **Storage key:** `"com.whiskey.personalVocabulary"`
///
/// **Constraints:**
/// - Maximum 50 terms.
/// - Terms are stored as entered; matching is case-insensitive for deduplication.
/// - Duplicate detection is case-insensitive: adding "xcode" when "Xcode" exists throws.
///
/// **Thread safety:** `@MainActor` -- all access must happen on the main actor.
@MainActor
public final class PersonalVocabularyStore: ObservableObject {

    // MARK: - Constants

    public static let userDefaultsKey = "com.whiskey.personalVocabulary"
    public static let maximumTermCount = 50

    // MARK: - Shared instance

    public static let shared = PersonalVocabularyStore()

    // MARK: - Storage

    private let defaults: UserDefaults

    // MARK: - Published state

    /// The ordered list of vocabulary terms as stored by the user.
    @Published public private(set) var terms: [String] = []

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Public API

    /// Adds a new term to the vocabulary.
    ///
    /// - Trims leading/trailing whitespace before validation.
    /// - Throws `PersonalVocabularyError.emptyTerm` if the result is empty.
    /// - Throws `PersonalVocabularyError.tooManyTerms` if 50 terms are already stored.
    /// - Throws `PersonalVocabularyError.duplicateTerm` if a case-insensitive match exists.
    ///
    /// On success, the term is appended and persisted immediately.
    public func add(_ term: String) throws {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw PersonalVocabularyError.emptyTerm
        }

        guard terms.count < Self.maximumTermCount else {
            throw PersonalVocabularyError.tooManyTerms(max: Self.maximumTermCount)
        }

        if let existing = terms.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            throw PersonalVocabularyError.duplicateTerm(existing: existing)
        }

        terms.append(trimmed)
        persist()
    }

    /// Removes the term matching `term` case-insensitively.
    ///
    /// If no match is found this is a no-op (safe to call with stale data).
    public func remove(_ term: String) {
        let before = terms.count
        terms.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        if terms.count != before {
            persist()
        }
    }

    /// A comma-joined string of all terms, suitable for Whisper's `initial_prompt`.
    ///
    /// Returns an empty string when no terms are stored.
    public var promptString: String {
        terms.joined(separator: ", ")
    }

    // MARK: - Persistence

    private func persist() {
        defaults.set(terms, forKey: Self.userDefaultsKey)
    }

    private func load() {
        terms = defaults.stringArray(forKey: Self.userDefaultsKey) ?? []
    }
}
