import Foundation

/// A saved text expansion triggered by a spoken phrase.
///
/// Trigger matching is case-insensitive at runtime; the trigger phrase is
/// stored exactly as the user entered it. Expansions are plain Unicode strings
/// with no variable substitution in Sprint 3 — `{date}` / `{time}` tokens are
/// treated as literal characters and reserved for Sprint 4+.
public struct Snippet: Identifiable, Codable, Sendable, Equatable {

    // MARK: - Properties

    /// Stable identifier. Never changes after creation.
    public let id: UUID

    /// The spoken phrase that triggers expansion.
    ///
    /// Must contain at least 3 whitespace-delimited words; enforced by
    /// `SnippetStore` at save time. Stored as entered; compared case-insensitively.
    public var triggerPhrase: String

    /// The text to inject when the trigger fires. May be multi-line.
    /// No variable substitution in Sprint 3.
    public var expansionText: String

    /// When `false` this snippet is excluded from trigger matching entirely.
    public var isEnabled: Bool

    /// UTC creation timestamp. Used as a tiebreaker when two triggers
    /// have the same word count — the earlier snippet wins.
    public let createdAt: Date

    /// UTC last-modification timestamp. Updated on every save.
    public var updatedAt: Date

    /// When `true` and `useCount == 0`, a preview banner is shown before
    /// the first injection. Once `useCount >= 1` the banner never appears
    /// regardless of this flag.
    public var previewNotificationEnabled: Bool

    /// Number of times this snippet was successfully expanded and injected.
    /// Zero means the snippet has never fired. Used to gate the first-use preview.
    public var useCount: Int

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case id
        case triggerPhrase
        case expansionText
        case isEnabled = "enabled"
        case createdAt
        case updatedAt
        case previewNotificationEnabled
        case useCount
    }

    // MARK: - Init

    /// Creates a new snippet.
    ///
    /// - Parameters:
    ///   - triggerPhrase: Spoken phrase. Must be >= 3 words at save time.
    ///   - expansionText: Text to inject.
    ///   - isEnabled: Whether this snippet participates in matching. Default `true`.
    public init(
        triggerPhrase: String,
        expansionText: String,
        isEnabled: Bool = true
    ) {
        self.id = UUID()
        self.triggerPhrase = triggerPhrase
        self.expansionText = expansionText
        self.isEnabled = isEnabled
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
        self.previewNotificationEnabled = true
        self.useCount = 0
    }

    // MARK: - Helpers

    /// Word count of the trigger phrase. Used for longest-match ranking.
    public var triggerWordCount: Int {
        triggerPhrase
            .split(whereSeparator: \.isWhitespace)
            .count
    }
}
