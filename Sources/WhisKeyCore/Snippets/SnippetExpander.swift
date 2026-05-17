import Foundation
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "SnippetExpander")

// MARK: - SnippetExpander

/// Pure, side-effect-free trigger matcher and text expander.
///
/// `SnippetExpander` has no dependency on `AXInjector`, `SnippetStore`, or any
/// other service. It receives a pre-fetched snapshot of snippets and a transcribed
/// string, and returns an `ExpandResult` when a trigger fires — or `nil` when no
/// trigger matches. All injection routing, safety checks, and persistence updates
/// are the responsibility of the pipeline coordinator.
///
/// Matching algorithm (per S3-C3 spec):
/// 1. Normalise `transcribedText`: lowercased, whitespace trimmed.
/// 2. Filter to enabled snippets; sort descending by word count, then character count,
///    then ascending creation date (oldest wins on full tie).
/// 3. For each candidate: case-insensitive substring search with word-boundary anchors.
/// 4. First (longest) match wins.
/// 5. Strip the trigger from the text and insert the expansion in its place.
public struct SnippetExpander: Sendable {

    // MARK: - Public API

    /// Scans `text` for a snippet trigger and returns the expansion result,
    /// or `nil` when no enabled snippet trigger is found.
    ///
    /// - Parameters:
    ///   - text: Fully post-processed transcription string (after Whisper + optional LLM cleanup).
    ///   - snippets: Snapshot of all snippets; disabled ones are filtered internally.
    /// - Returns: An `ExpandResult` on match, or `nil`.
    public static func expand(_ text: String, snippets: [Snippet]) -> ExpandResult? {
        guard !text.isEmpty, !snippets.isEmpty else { return nil }

        let normalised = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let candidates = snippets
            .filter { $0.isEnabled }
            .sorted { lhs, rhs in
                if lhs.triggerWordCount != rhs.triggerWordCount {
                    return lhs.triggerWordCount > rhs.triggerWordCount
                }
                if lhs.triggerPhrase.count != rhs.triggerPhrase.count {
                    return lhs.triggerPhrase.count > rhs.triggerPhrase.count
                }
                return lhs.createdAt < rhs.createdAt
            }

        for (index, snippet) in candidates.enumerated() {
            let normTrigger = snippet.triggerPhrase
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            guard !normTrigger.isEmpty else { continue }

            guard let range = wordBoundaryRange(of: normTrigger, in: normalised) else { continue }

            // Conflict log: warn when we resolved a same-length tie by creation date.
            if index > 0 {
                let prev = candidates[index - 1]
                if prev.triggerWordCount == snippet.triggerWordCount,
                   prev.triggerPhrase.count == snippet.triggerPhrase.count {
                    logger.warning("SnippetExpander: trigger tie resolved by creation date. Winner: \(snippet.triggerPhrase). Consider making triggers distinct.")
                }
            }

            let expanded = applyExpansion(
                originalText: text,
                normalisedText: normalised,
                triggerRange: range,
                expansion: snippet.expansionText
            )

            return ExpandResult(
                originalText: text,
                expandedText: expanded,
                matchedSnippet: snippet
            )
        }

        return nil
    }

    // MARK: - Result

    /// The result of a successful snippet expansion.
    public struct ExpandResult: Sendable {
        /// The original transcribed text before expansion.
        public let originalText: String
        /// The text after the trigger phrase was replaced with the expansion.
        public let expandedText: String
        /// The snippet whose trigger phrase matched.
        public let matchedSnippet: Snippet
    }

    // MARK: - Private Helpers

    /// Finds the range of `trigger` in `text` with word-boundary enforcement.
    ///
    /// Leading boundary: start-of-string or a space character.
    /// Trailing boundary: end-of-string, a space, or a punctuation character.
    ///
    /// Both arguments must be pre-normalised (lowercased, whitespace-collapsed).
    /// Returns `nil` when no word-boundary-anchored match exists.
    private static func wordBoundaryRange(of trigger: String, in text: String) -> Range<String.Index>? {
        var searchStart = text.startIndex

        while searchStart < text.endIndex {
            guard let found = text.range(
                of: trigger,
                options: .caseInsensitive,
                range: searchStart ..< text.endIndex
            ) else {
                return nil
            }

            let atStart = found.lowerBound == text.startIndex
            let leadOK: Bool
            if atStart {
                leadOK = true
            } else {
                leadOK = text[text.index(before: found.lowerBound)] == " "
            }

            let atEnd = found.upperBound == text.endIndex
            let trailOK: Bool
            if atEnd {
                trailOK = true
            } else {
                let ch = text[found.upperBound]
                trailOK = ch == " " || ch.isPunctuation
            }

            if leadOK && trailOK {
                return found
            }

            searchStart = text.index(after: found.lowerBound)
        }

        return nil
    }

    /// Replaces the trigger substring with `expansion`, trimming double-spaces.
    ///
    /// When the trigger is the entire text, the expansion replaces it wholesale
    /// (the common "say only the trigger phrase" case).
    private static func applyExpansion(
        originalText: String,
        normalisedText: String,
        triggerRange: Range<String.Index>,
        expansion: String
    ) -> String {
        // Full-text match: replace entirely.
        if triggerRange.lowerBound == normalisedText.startIndex,
           triggerRange.upperBound == normalisedText.endIndex {
            return expansion
        }

        // Embedded match: map character offsets from normalised to original text.
        // The normalised string is produced by lowercasing the original, so
        // Swift Character offsets are identical (lowercasing does not change
        // Character count for any Unicode scalar that whisper output contains).
        let leadOffset = normalisedText.distance(
            from: normalisedText.startIndex,
            to: triggerRange.lowerBound
        )
        let triggerLen = normalisedText.distance(
            from: triggerRange.lowerBound,
            to: triggerRange.upperBound
        )

        let origStart = originalText.index(originalText.startIndex, offsetBy: leadOffset)
        let origEnd = originalText.index(origStart, offsetBy: triggerLen)

        var result = originalText
        result.replaceSubrange(origStart ..< origEnd, with: expansion)

        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
