import Foundation

/// Controls how long the live-preview caption strip remains visible after
/// the final Whisper transcript is injected.
///
/// P1 hardcodes `.untilInjected`. P2 persists the user's choice via
/// `SettingsKey.previewLingerMode` and a `SettingsManager` accessor.
public enum PreviewLingerMode: Sendable, Equatable, Hashable {
    /// Clear immediately when recording stops (before Whisper completes).
    case immediate
    /// Clear after the final transcript is injected (P1 default).
    case untilInjected
    /// Clear after a fixed delay following injection.
    case linger(seconds: Double)
    /// Hold on error until the user dismisses (runtime-only; never persisted).
    case errorHold
}

// MARK: - Codable

/// Manual `Codable` so the stored JSON is stable and human-readable.
/// `.errorHold` is a runtime-only state; it is never written to the settings
/// store. The decoder falls back to `.linger(seconds: 2)` for any unknown
/// or corrupt stored value.
extension PreviewLingerMode: Codable {
    private enum CodingKeys: String, CodingKey { case type, seconds }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .immediate:
            try container.encode("immediate", forKey: .type)
        case .untilInjected:
            try container.encode("untilInjected", forKey: .type)
        case .linger(let seconds):
            try container.encode("linger", forKey: .type)
            try container.encode(seconds, forKey: .seconds)
        case .errorHold:
            // errorHold is never persisted; encode as the safe default.
            try container.encode("linger", forKey: .type)
            try container.encode(2.0, forKey: .seconds)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "immediate":
            self = .immediate
        case "untilInjected":
            self = .untilInjected
        case "linger":
            self = .linger(seconds: try container.decode(Double.self, forKey: .seconds))
        default:
            self = .linger(seconds: 2)
        }
    }
}
