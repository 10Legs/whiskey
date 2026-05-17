/// Registry of application bundle IDs that must never receive re-injected text.
///
/// These targets can contain credentials, sudo prompts, or security-sensitive
/// input fields. Injecting transcription text into them without explicit user
/// intent could cause irreversible or security-critical side effects.
public struct SensitiveAppRegistry: Sendable {

    /// Bundle IDs blocked from receiving re-injected text.
    public static let blocklist: Set<String> = [
        "com.apple.keychainaccess",
        "com.apple.systempreferences",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.authy.authy-mac",
        "com.microsoft.authenticator",
        "com.apple.SecurityAgent"
    ]

    /// Returns `true` when the given bundle ID is on the sensitivity blocklist.
    ///
    /// A `nil` bundle ID is treated as safe so that apps without a bundle ID
    /// (rare edge cases) do not silently block legitimate injection targets.
    public static func isSensitive(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return blocklist.contains(id)
    }
}
