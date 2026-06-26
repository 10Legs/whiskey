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

    /// Per-app text-injection strategy. `.auto` runs the full waterfall (default).
    /// See ADR-009: Per-App Injection-Method Override.
    public var injectionMethod: InjectionMethod

    // MARK: - Init

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        displayName: String,
        modelID: String? = nil,
        languageHint: String? = nil,
        cleanupProfile: CleanupProfile = CleanupProfile(),
        enabled: Bool = true,
        injectionMethod: InjectionMethod = .auto
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.modelID = modelID
        self.languageHint = languageHint
        self.cleanupProfile = cleanupProfile
        self.enabled = enabled
        self.injectionMethod = injectionMethod
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

    // MARK: - Seeded default profiles (ADR-009)

    /// Seeded profile for Messages — AX compose field lies; Paste (Cmd-V) is reliable.
    public static func seededMessages() -> AppProfile {
        AppProfile(
            bundleIdentifier: "com.apple.MobileSMS",
            displayName: "Messages",
            injectionMethod: .pasteboard
        )
    }

    /// Seeded profile for Telegram Desktop — AX silently drops writes; Paste is reliable.
    public static func seededTelegramDesktop() -> AppProfile {
        AppProfile(
            bundleIdentifier: "com.tdesktop.Telegram",
            displayName: "Telegram",
            injectionMethod: .pasteboard
        )
    }

    /// Seeded profile for the alternative Telegram bundle (ru.keepcoder.Telegram).
    public static func seededTelegramAlt() -> AppProfile {
        AppProfile(
            bundleIdentifier: "ru.keepcoder.Telegram",
            displayName: "Telegram",
            injectionMethod: .pasteboard
        )
    }
}

// MARK: - Codable conformance for AppProfile (custom decoder for backward-compat)
//
// Synthesized `Codable` does not apply Swift default-argument values during decoding:
// a missing key throws `keyNotFound` and would crash every existing persisted profile.
// Solution: custom init(from:) using decodeIfPresent with fallbacks. Any uncertainty
// (key absent OR unrecognized raw value) resolves to `.auto`. See ADR-009 §2.

extension AppProfile {
    enum CodingKeys: String, CodingKey {
        case id, bundleIdentifier, displayName, modelID,
             languageHint, cleanupProfile, enabled, injectionMethod
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id               = try container.decode(UUID.self, forKey: .id)
        self.bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        self.displayName      = try container.decode(String.self, forKey: .displayName)
        self.modelID          = try container.decodeIfPresent(String.self, forKey: .modelID)
        self.languageHint     = try container.decodeIfPresent(String.self, forKey: .languageHint)
        self.cleanupProfile   = try container.decode(CleanupProfile.self, forKey: .cleanupProfile)
        self.enabled          = try container.decode(Bool.self, forKey: .enabled)
        // Use try? so an unrecognized future raw value also resolves to .auto.
        self.injectionMethod  = (try? container.decodeIfPresent(InjectionMethod.self,
                                                                forKey: .injectionMethod)) ?? .auto
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(modelID, forKey: .modelID)
        try container.encodeIfPresent(languageHint, forKey: .languageHint)
        try container.encode(cleanupProfile, forKey: .cleanupProfile)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(injectionMethod, forKey: .injectionMethod)
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
