import Foundation

/// Post-Whisper regex pass that removes common spoken filler words from transcript text.
///
/// Pure function, no state, `Sendable`. Runs after Whisper inference and before the LLM
/// cleanup step. The scrubber removes a curated word list only — more aggressive patterns
/// ("like", "actually") are excluded in v1 per ADR-sprint1-silence-trim to avoid
/// false-positive removal in legitimate sentence usage.
///
/// Removed: um/umm, uh/uhh, hmm/hmmm, er/err, ah/ahh (word-boundary aware, case-insensitive).
public struct FillerScrubber: Sendable {

    // MARK: - Public API

    /// Remove filler words from a transcript string.
    ///
    /// - Parameter text: Raw Whisper transcript.
    /// - Returns: Cleaned text with fillers removed and whitespace normalized.
    public static func scrub(_ text: String) -> String {
        var result = text
        result = applyFillerPattern(to: result)
        result = normalizeWhitespace(result)
        return result
    }

    // MARK: - Internal Helpers

    /// Applies a single regex pass covering all filler variants.
    /// Uses `.regularExpression` + `.caseInsensitive` — no `NSRegularExpression` boilerplate.
    static func applyFillerPattern(to text: String) -> String {
        // Pattern covers repeated vowels (um+, uh+, er+, ah+, hmm+) and word boundaries.
        let pattern = "\\b(um+|uh+|hmm+|er+|ah+)\\b"
        var result = text
        // Iteratively replace to handle adjacent fillers separated by spaces.
        while let range = result.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
            result.replaceSubrange(range, with: "")
        }
        return result
    }

    /// Collapses multiple consecutive whitespace characters into a single space,
    /// trims leading/trailing whitespace, and removes space before sentence-ending punctuation.
    static func normalizeWhitespace(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        // Remove space immediately before sentence-ending punctuation.
        result = result.replacingOccurrences(
            of: "\\s+([.,!?;:])",
            with: "$1",
            options: .regularExpression
        )
        return result
    }
}
