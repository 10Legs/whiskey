import Foundation
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "AppToneProfileStore")

// MARK: - AppToneProfileError

public enum AppToneProfileError: Error, LocalizedError {
    /// The bundle ID is empty or does not conform to reverse-DNS format.
    case invalidBundleID
    /// The bundle ID exceeds the maximum allowed length.
    case bundleIDTooLong(max: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidBundleID:
            return "Bundle IDs must be in reverse-DNS format (e.g. com.apple.Terminal)."
        case .bundleIDTooLong(let max):
            return "Bundle IDs cannot exceed \(max) characters."
        }
    }
}

/// Persists per-app `ToneProfile` mappings in `UserDefaults`.
///
/// Maps bundle identifier strings to `ToneProfile` values.
/// Defaults to `.casual` for any app that has no explicit mapping.
///
/// All access is `@MainActor`-isolated because the store is observed by SwiftUI
/// views via `@Observable` and mutated from UI callbacks.
@Observable
@MainActor
public final class AppToneProfileStore {

    // MARK: - Constants

    public static let maximumBundleIDLength = 255
    private static let bundleIDPattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"^[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+){1,}$"#)
        } catch {
            fatalError("bundleIDPattern regex is invalid: \(error)")
        }
    }()

    // MARK: - Singleton

    public static let shared = AppToneProfileStore()

    // MARK: - Storage

    private static let defaultsKey = "com.whiskey.appToneProfiles"

    /// In-memory representation of the persisted mapping.
    private var mappings: [String: ToneProfile] = [:]

    /// The UserDefaults suite used for persistence.
    /// Injected at init so tests can use an isolated suite.
    private let defaults: UserDefaults

    // MARK: - Init

    /// Production init — uses `UserDefaults.standard`.
    public init() {
        self.defaults = .standard
        load()
    }

    /// Test init — accepts an isolated `UserDefaults` suite.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
        load()
    }

    // MARK: - CRUD

    /// Returns the `ToneProfile` configured for `bundleID`,
    /// or `.casual` when no explicit mapping exists.
    public func profile(for bundleID: String) -> ToneProfile {
        mappings[bundleID] ?? .casual
    }

    /// Persists `profile` for the given `bundleID`, replacing any prior value.
    ///
    /// - Throws: `AppToneProfileError.bundleIDTooLong` when `bundleID` exceeds 255 characters.
    /// - Throws: `AppToneProfileError.invalidBundleID` when `bundleID` does not match
    ///   reverse-DNS format (`^[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+){1,}$`).
    public func setProfile(_ profile: ToneProfile, for bundleID: String) throws {
        guard bundleID.count <= Self.maximumBundleIDLength else {
            throw AppToneProfileError.bundleIDTooLong(max: Self.maximumBundleIDLength)
        }
        let range = NSRange(bundleID.startIndex..., in: bundleID)
        guard Self.bundleIDPattern.firstMatch(in: bundleID, range: range) != nil else {
            throw AppToneProfileError.invalidBundleID
        }
        mappings[bundleID] = profile
        save()
    }

    /// Removes the mapping for `bundleID`. Subsequent lookups return `.casual`.
    public func removeProfile(for bundleID: String) {
        mappings.removeValue(forKey: bundleID)
        save()
    }

    /// All configured mappings, sorted ascending by bundle identifier.
    public var allMappings: [(bundleID: String, profile: ToneProfile)] {
        mappings
            .sorted { $0.key < $1.key }
            .map { (bundleID: $0.key, profile: $0.value) }
    }

    // MARK: - Persistence

    private func load() {
        guard let raw = defaults.dictionary(forKey: Self.defaultsKey)
                as? [String: String] else {
            return
        }
        var decoded: [String: ToneProfile] = [:]
        for (bundleID, rawValue) in raw {
            if let profile = ToneProfile(rawValue: rawValue) {
                decoded[bundleID] = profile
            } else {
                logger.warning("AppToneProfileStore: unknown ToneProfile '\(rawValue)' for '\(bundleID)' — skipped.")
            }
        }
        mappings = decoded
        logger.info("AppToneProfileStore: loaded \(decoded.count) mapping(s).")
    }

    private func save() {
        let raw = mappings.mapValues(\.rawValue)
        defaults.set(raw, forKey: Self.defaultsKey)
        logger.info("AppToneProfileStore: saved \(self.mappings.count) mapping(s).")
    }
}
