import CoreGraphics
import Foundation

// MARK: - Reserved Combo

/// A macOS-reserved key combo that must not be bound to a WhisKey action.
public struct ReservedHotkey: Sendable {
    public let keyCode: CGKeyCode
    public let modifierFlags: CGEventFlags

    public init(keyCode: CGKeyCode, modifierFlags: CGEventFlags) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }
}

// MARK: - HotkeyBindingStore

/// Persists user-configured `HotkeyBinding` values to `UserDefaults`.
///
/// **Storage key:** `"com.whiskey.hotkeyBindings"`
///
/// **Default binding:** `defaultTranscription` → Right Option (keyCode 0x3D, no modifiers).
/// All other actions default to no binding.
///
/// **Migration:** On first access, if the legacy `"whiskey.hotkey"` UserDefaults key is
/// present and the new key is absent, the default binding is written and the legacy key
/// is left untouched (migration is additive and idempotent).
@MainActor
public final class HotkeyBindingStore: ObservableObject {

    // MARK: - Constants

    public static let userDefaultsKey = "com.whiskey.hotkeyBindings"
    private static let legacyKey = "whiskey.hotkey"

    // MARK: - Reserved macOS combos (minimum block list per spec §6)
    //
    // Loaded inline — a future sprint can replace this with a bundled JSON resource
    // by adding a resources stanza to the WhisKeyCore target in Package.swift.

    public static let reservedCombos: [ReservedHotkey] = [
        // ⌘Q — Quit
        .init(keyCode: 0x0C, modifierFlags: .maskCommand),
        // ⌘H — Hide
        .init(keyCode: 0x04, modifierFlags: .maskCommand),
        // ⌘M — Minimize
        .init(keyCode: 0x2E, modifierFlags: .maskCommand),
        // ⌘W — Close window
        .init(keyCode: 0x0D, modifierFlags: .maskCommand),
        // ⌘Tab — App switcher (keyCode 0x30 = Tab)
        .init(keyCode: 0x30, modifierFlags: .maskCommand),
        // ⌘Space — Spotlight
        .init(keyCode: 0x31, modifierFlags: .maskCommand),
        // ⌘⇧Space — Spotlight alternate
        .init(keyCode: 0x31, modifierFlags: [.maskCommand, .maskShift]),
        // ⌘` — Cycle windows (keyCode 0x32 = backtick/grave)
        .init(keyCode: 0x32, modifierFlags: .maskCommand),
        // ⌘, — Preferences (keyCode 0x2B = comma)
        .init(keyCode: 0x2B, modifierFlags: .maskCommand),
        // ⌃Space — Input source switcher
        .init(keyCode: 0x31, modifierFlags: .maskControl),
        // ⌃F2 — Menu bar focus (keyCode 0x78 = F2)
        .init(keyCode: 0x78, modifierFlags: .maskControl),
        // ⌃F3 — Dock focus (keyCode 0x63 = F3)
        .init(keyCode: 0x63, modifierFlags: .maskControl),
        // ⌃F8 — Status menu focus (keyCode 0x64 = F8... wait: F8 = 0x64)
        .init(keyCode: 0x64, modifierFlags: .maskControl)
    ]

    // MARK: - Storage

    private let defaults: UserDefaults

    /// In-memory cache, keyed by action raw value.
    private var cache: [String: HotkeyBinding] = [:]

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadOrMigrate()
    }

    // MARK: - Public API

    /// Returns the current binding for the given action.
    public func binding(for action: HotkeyAction) -> HotkeyBinding {
        cache[action.rawValue] ?? HotkeyBinding(action: action)
    }

    /// Persists a binding and updates the in-memory cache.
    public func setBinding(_ binding: HotkeyBinding) {
        cache[binding.action.rawValue] = binding
        persist()
    }

    /// Removes the binding for the given action (sets it to "not set").
    public func clearBinding(for action: HotkeyAction) {
        cache[action.rawValue] = HotkeyBinding(action: action)
        persist()
    }

    /// Returns the `HotkeyAction` that already owns the given key combo, excluding
    /// `excluding` (used during recording so the row being edited doesn't conflict
    /// with its own current value).
    ///
    /// Returns nil if no conflict exists.
    public func conflictingAction(
        for keyCode: CGKeyCode,
        modifierFlags: CGEventFlags?,
        excluding: HotkeyAction?
    ) -> HotkeyAction? {
        for action in HotkeyAction.allCases {
            guard action != excluding else { continue }
            let existing = binding(for: action)
            guard let existingCode = existing.keyCode else { continue }
            let flagsMatch: Bool = {
                switch (existing.modifierFlags, modifierFlags) {
                case (.none, .none): return true
                case (.some(let lhs), .some(let rhs)): return lhs == rhs
                default: return false
                }
            }()
            if existingCode == keyCode && flagsMatch {
                return action
            }
        }
        return nil
    }

    /// Returns true if the given key combo is on the macOS reserved list.
    public func isReserved(keyCode: CGKeyCode, modifierFlags: CGEventFlags?) -> Bool {
        for reserved in Self.reservedCombos {
            let flagsMatch: Bool = {
                let rf = modifierFlags ?? []
                return reserved.modifierFlags == rf
            }()
            if reserved.keyCode == keyCode && flagsMatch {
                return true
            }
        }
        return false
    }

    // MARK: - Persistence

    private func persist() {
        let bindings = Array(cache.values)
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        defaults.set(data, forKey: Self.userDefaultsKey)
    }

    private func loadOrMigrate() {
        if let data = defaults.data(forKey: Self.userDefaultsKey),
           let bindings = try? JSONDecoder().decode([HotkeyBinding].self, from: data) {
            for binding in bindings {
                cache[binding.action.rawValue] = binding
            }
            // Fill in any actions not yet present in persisted data.
            seedMissingDefaults()
        } else {
            // No persisted bindings. Seed defaults (migrating from legacy key if present).
            seedDefaults()
        }
    }

    /// Write default bindings for any action that has no entry in the cache.
    private func seedMissingDefaults() {
        // defaultTranscription is the only action with a non-nil default.
        if cache[HotkeyAction.defaultTranscription.rawValue]?.keyCode == nil {
            cache[HotkeyAction.defaultTranscription.rawValue] = Self.defaultTranscriptionBinding
        }
    }

    private func seedDefaults() {
        // Migration: if the legacy key exists we respect it as confirmation that
        // the user had the app running before (idempotent on subsequent launches).
        // The legacy key is left untouched.
        _ = defaults.object(forKey: Self.legacyKey)

        // Default: Right Option for defaultTranscription.
        cache[HotkeyAction.defaultTranscription.rawValue] = Self.defaultTranscriptionBinding
        persist()
    }

    // MARK: - Defaults

    public static let defaultTranscriptionBinding = HotkeyBinding(
        action: .defaultTranscription,
        keyCode: CGKeyCode(0x3D), // Right Option
        modifierFlags: nil
    )
}
