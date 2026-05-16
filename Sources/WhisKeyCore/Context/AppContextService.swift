import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.whiskey.app", category: "AppContextService")

/// Observes frontmost-application changes via `NSWorkspace` and resolves the
/// matching `AppProfile` for use by `TranscriptionPipeline`.
///
/// Must be owned on the main thread (`@MainActor`). Create once in `AppDelegate`,
/// call `start()` after launch, and inject into `TranscriptionPipeline.appContextService`.
///
/// Resolution order per `AppProfile` ADR:
/// 1. Exact bundle ID match where `enabled == true`.
/// 2. Wildcard profile (`bundleIdentifier == "*"`).
/// 3. Synthesised fallback built from global `SettingsManager` values (preserves
///    pre-Sprint-1 pipeline behaviour for users with no profiles defined).
@MainActor
public final class AppContextService: ObservableObject {

    // MARK: - Published state

    /// Bundle identifier of the current frontmost application.
    @Published public private(set) var currentBundleID: String = ""

    /// Resolved profile for the current frontmost application.
    @Published public private(set) var activeProfile: AppProfile

    // MARK: - Dependencies

    private let settings: SettingsManager
    private var observer: NSObjectProtocol?

    // MARK: - Init

    public init(settingsManager: SettingsManager) {
        self.settings = settingsManager
        // Start with the global default so the property is never uninitialised.
        self.activeProfile = AppProfile.makeDefault()
    }

    // MARK: - Lifecycle

    /// Install the `NSWorkspace` observer and resolve the initial profile.
    public func start() {
        resolveCurrentApp()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self.handleAppActivation(bundleID: app?.bundleIdentifier ?? "")
        }
        logger.info("AppContextService started.")
    }

    /// Remove the observer. Call from `applicationWillTerminate(_:)` or deinit.
    public func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        logger.info("AppContextService stopped.")
    }

    // MARK: - Internal resolution

    private func resolveCurrentApp() {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        handleAppActivation(bundleID: bundleID)
    }

    private func handleAppActivation(bundleID: String) {
        currentBundleID = bundleID
        activeProfile = resolve(bundleID: bundleID)
        logger.info("Active app: \(bundleID) → profile: \(self.activeProfile.displayName)")
    }

    /// Resolve which `AppProfile` applies to `bundleID`.
    private func resolve(bundleID: String) -> AppProfile {
        let profiles = settings.appProfiles

        // 1. Exact match.
        if let exact = profiles.first(where: { $0.bundleIdentifier == bundleID && $0.enabled }) {
            return exact
        }

        // 2. Wildcard default profile.
        if let wildcard = profiles.first(where: { $0.bundleIdentifier == "*" && $0.enabled }) {
            return wildcard
        }

        // 3. Synthesised fallback from global settings — preserves pre-Sprint-1 behaviour.
        return AppProfile(
            bundleIdentifier: "*",
            displayName: "Default",
            modelID: settings.activeModelID,
            languageHint: settings.languageHint,
            cleanupProfile: settings.cleanupProfile,
            enabled: true
        )
    }
}
