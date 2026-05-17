import Foundation

/// A transcription configuration bundle keyed by application bundle identifier.
///
/// A profile with `bundleIdentifier == "*"` is the system default and matches
/// all apps that have no explicit profile. Resolution order in `AppContextService`:
/// 1. Exact bundle ID match (enabled == true).
/// 2. Wildcard profile (bundleIdentifier == "*").
/// 3. Global SettingsManager defaults (existing pre-Sprint-1 behaviour).
public struct AppProfile: Codable, Identifiable, Sendable {

    // MARK: - Properties

    public let id: UUID

    /// The application bundle identifier this profile applies to.
    /// Use `"*"` for the catch-all default profile.
    public var bundleIdentifier: String

    /// Human-readable name shown in the App Profiles settings UI.
    public var displayName: String

    /// Whisper model to use for this app. `nil` inherits the global `activeModelID`.
    public var modelID: String?

    /// BCP-47 language hint passed to Whisper. `nil` = auto-detect or global setting.
    public var languageHint: String?

    /// LLM cleanup configuration applied during transcription for this app.
    public var cleanupProfile: CleanupProfile

    /// When `false` the profile is stored but not applied. Allows toggling without deletion.
    public var enabled: Bool

    // MARK: - Init

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        displayName: String,
        modelID: String? = nil,
        languageHint: String? = nil,
        cleanupProfile: CleanupProfile = CleanupProfile(),
        enabled: Bool = true
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.modelID = modelID
        self.languageHint = languageHint
        self.cleanupProfile = cleanupProfile
        self.enabled = enabled
    }

    // MARK: - Factory

    /// The built-in catch-all default profile. Always present; cannot be deleted by the user.
    public static func makeDefault() -> AppProfile {
        AppProfile(
            bundleIdentifier: "*",
            displayName: "Default",
            cleanupProfile: CleanupProfile(),
            enabled: true
        )
    }
}

// MARK: - Codable conformance for CleanupProfile

extension CleanupProfile: Codable {
    enum CodingKeys: String, CodingKey {
        case removeFillers, addPunctuation, toneStyle, rawMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.removeFillers = try container.decode(Bool.self, forKey: .removeFillers)
        self.addPunctuation = try container.decode(Bool.self, forKey: .addPunctuation)
        let toneRaw = try container.decode(String.self, forKey: .toneStyle)
        self.toneStyle = ToneStyle(rawValue: toneRaw) ?? .casual
        self.rawMode = try container.decode(Bool.self, forKey: .rawMode)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(removeFillers, forKey: .removeFillers)
        try container.encode(addPunctuation, forKey: .addPunctuation)
        try container.encode(toneStyle.rawValue, forKey: .toneStyle)
        try container.encode(rawMode, forKey: .rawMode)
    }
}
