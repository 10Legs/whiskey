import Foundation
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "VoiceCommandProcessor")

/// A voice command recognized within a transcription utterance.
///
/// Commands are stripped from the injected text and executed as discrete actions.
/// Unrecognized text passes through unchanged.
public enum VoiceCommand: Sendable, Equatable {
    /// "new paragraph" — append `\n\n` to the text before it.
    case insertNewParagraph
    /// "new line" — append `\n` to the text before it.
    case insertNewLine
    /// "scratch that" / "delete that" — delete the last injected utterance.
    case deleteLastUtterance
    /// "all caps" — uppercase the last word in the text before it.
    case uppercaseLastWord
    /// "period" — insert a `.` character.
    case insertPeriod
    /// "comma" — insert a `,` character.
    case insertComma
    /// "question mark" — insert a `?` character.
    case insertQuestionMark
}

/// The result of processing a raw transcript through `VoiceCommandProcessor`.
public struct VoiceCommandResult: Sendable {
    /// The transcript with all recognized command phrases stripped.
    /// Unrecognized text is preserved verbatim.
    public let cleanedText: String

    /// Commands found in order of appearance. Execute these after injecting
    /// `cleanedText` into the focused element.
    public let commands: [VoiceCommand]
}

/// Scans a raw Whisper transcript for recognized voice command phrases,
/// strips them from the output, and returns the list of commands to execute.
///
/// Matching rules:
/// - Case-insensitive.
/// - Whole-phrase boundary match (space, punctuation, or string edge on both sides).
/// - Multiple commands in one utterance are all detected, in left-to-right order.
/// - At each scan position the leftmost match across ALL phrases wins (not the
///   first entry in the command table), ensuring correct ordering when multiple
///   commands appear in the same utterance.
/// - Phrases are stripped regardless of whether the command is fully implemented.
public struct VoiceCommandProcessor: Sendable {

    // MARK: - Command table

    private static let commandTable: [(phrases: [String], command: VoiceCommand)] = [
        (["new paragraph"], .insertNewParagraph),
        (["new line"], .insertNewLine),
        (["scratch that", "delete that"], .deleteLastUtterance),
        (["all caps"], .uppercaseLastWord),
        (["question mark"], .insertQuestionMark),
        (["period"], .insertPeriod),
        (["comma"], .insertComma)
    ]

    public init() {}

    // MARK: - Public API

    /// Process `transcript`, returning cleaned text and the list of commands.
    ///
    /// Uses NSString UTF-16 offsets for all position arithmetic so that
    /// indices remain valid after each in-place phrase removal.
    public func process(_ transcript: String) -> VoiceCommandResult {
        var working = transcript
        var commands: [VoiceCommand] = []
        var scanOffset = 0

        while scanOffset < (working as NSString).length {
            // Find the leftmost whole-phrase match across ALL command phrases
            // starting at or after scanOffset.
            if let best = findLeftmostMatch(in: working, fromUTF16Offset: scanOffset) {
                commands.append(best.command)
                let ns = NSMutableString(string: working)
                ns.deleteCharacters(in: best.absorb)
                working = ns as String
                // Resume scanning at the deletion start — another command may
                // immediately follow in the compacted string.
                scanOffset = best.absorb.location
            } else {
                // No command phrase found from here to end of string.
                break
            }
        }

        let cleaned = working.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.debug("VoiceCommandProcessor: \(commands.count) command(s) extracted; cleaned=\(cleaned.count) chars")
        return VoiceCommandResult(cleanedText: cleaned, commands: commands)
    }

    // MARK: - Private helpers

    /// A matched voice command with its NS ranges used for phrase removal.
    private struct CommandMatch {
        let command: VoiceCommand
        let matchRange: NSRange
        let absorb: NSRange
    }

    /// Scans all command phrases from `fromOffset` and returns the one whose
    /// match position is smallest (leftmost). When two phrases tie on position,
    /// the longer phrase (earlier in table) wins.
    private func findLeftmostMatch(
        in text: String,
        fromUTF16Offset fromOffset: Int
    ) -> CommandMatch? {
        let ns = text as NSString
        var best: CommandMatch?

        for entry in Self.commandTable {
            for phrase in entry.phrases {
                guard let (matchRange, absorb) = firstWholePhraseMatch(
                    of: phrase,
                    in: ns,
                    fromUTF16Offset: fromOffset
                ) else { continue }

                if let current = best {
                    // Prefer the leftmost match; on ties prefer the one already found
                    // (earlier in table = higher priority for same position).
                    if matchRange.location < current.matchRange.location {
                        best = CommandMatch(command: entry.command, matchRange: matchRange, absorb: absorb)
                    }
                } else {
                    best = CommandMatch(command: entry.command, matchRange: matchRange, absorb: absorb)
                }
            }
        }

        return best
    }

    /// Searches for the first whole-phrase occurrence of `phrase` in `ns`
    /// starting at UTF-16 offset `fromOffset`.
    ///
    /// Returns `(matchRange, absorb)` where `absorb` is the range to delete
    /// (expands by one surrounding whitespace to prevent double-spaces).
    private func firstWholePhraseMatch(
        of phrase: String,
        in ns: NSString,
        fromUTF16Offset fromOffset: Int
    ) -> (matchRange: NSRange, absorb: NSRange)? {
        let total = ns.length
        var searchFrom = fromOffset

        while searchFrom < total {
            let searchRange = NSRange(location: searchFrom, length: total - searchFrom)
            let found = ns.range(of: phrase, options: [.caseInsensitive], range: searchRange)
            guard found.location != NSNotFound else { return nil }

            if isWholePhraseMatch(ns: ns, at: found) {
                let absorb = buildAbsorbRange(ns: ns, match: found)
                return (found, absorb)
            }
            searchFrom = found.location + 1
        }
        return nil
    }

    /// Returns `true` when the characters flanking `range` in `ns` are word
    /// boundaries (whitespace, punctuation, symbol, or string edge).
    private func isWholePhraseMatch(ns: NSString, at range: NSRange) -> Bool {
        let isBoundary: (unichar) -> Bool = { charCode in
            // unichar is UInt16; all BMP characters have non-optional Unicode.Scalar
            guard let scalar = Unicode.Scalar(charCode) else { return false }
            return CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)
        }

        let leadOK: Bool
        if range.location == 0 {
            leadOK = true
        } else {
            leadOK = isBoundary(ns.character(at: range.location - 1))
        }

        let trailOK: Bool
        let endIdx = range.location + range.length
        if endIdx >= ns.length {
            trailOK = true
        } else {
            trailOK = isBoundary(ns.character(at: endIdx))
        }

        return leadOK && trailOK
    }

    /// Returns the NSRange to delete for `match`, absorbing one adjacent
    /// whitespace to avoid leaving a double-space after stripping.
    private func buildAbsorbRange(ns: NSString, match: NSRange) -> NSRange {
        var lo = match.location
        var hi = match.location + match.length

        if lo > 0,
           let scalar = Unicode.Scalar(ns.character(at: lo - 1)),
           CharacterSet.whitespaces.contains(scalar) {
            lo -= 1
        } else if hi < ns.length,
                  let scalar = Unicode.Scalar(ns.character(at: hi)),
                  CharacterSet.whitespaces.contains(scalar) {
            hi += 1
        }

        return NSRange(location: lo, length: hi - lo)
    }
}
