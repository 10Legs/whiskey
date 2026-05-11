import Foundation
import os.log
import UserNotifications

private let logger = Logger(subsystem: "com.whiskey.app", category: "AppNotifications")

/// Fire-and-forget system notification facade for WhisKey pipeline errors.
///
/// All call sites are synchronous. Auth negotiation and delivery are handled
/// internally via a detached `Task`. Notification Center calls execute on the
/// main thread as required by `UNUserNotificationCenter`.
///
/// ## Bundle-environment safety
///
/// `UNUserNotificationCenter.current()` asserts that the running process has a
/// valid `bundleProxyForCurrentProcess` (i.e. it is launched as a proper `.app`
/// bundle). When WhisKey is run from a Swift Package binary in DerivedData,
/// from a unit-test host, or from any context without a registered bundle,
/// invoking `current()` will crash with a runtime assertion.
///
/// `AppNotifications` probes the environment exactly once and degrades to a
/// silent no-op (with a log line) whenever the bundle proxy is unavailable.
@MainActor
public enum AppNotifications {

    // MARK: - Category

    public enum Category {
        case modelMissing
        case downloadFailed(Error)
        case permissionDenied(String)
        case injectionFailed(String)
        case transcriptionFailed(Error)
        case hotkeyUnavailable(String)
        case captureUnavailable(String)
        case internalError(String)

        var title: String {
            switch self {
            case .modelMissing:
                return "Whisper Model Missing"
            case .downloadFailed:
                return "Download Failed"
            case .permissionDenied:
                return "Permission Required"
            case .injectionFailed:
                return "Text Injection Failed"
            case .transcriptionFailed:
                return "Transcription Failed"
            case .hotkeyUnavailable:
                return "Hotkey Unavailable"
            case .captureUnavailable:
                return "Audio Capture Unavailable"
            case .internalError:
                return "WhisKey Internal Error"
            }
        }

        var body: String {
            switch self {
            case .modelMissing:
                return "The Whisper model file is missing. Open Settings to download it."
            case .downloadFailed(let error):
                return "Could not download the model: \(error.localizedDescription)"
            case .permissionDenied(let detail):
                return "A required permission was denied: \(detail). Open System Settings to grant access."
            case .injectionFailed(let reason):
                return "Text could not be injected into the focused window: \(reason)"
            case .transcriptionFailed(let error):
                return "Transcription could not be completed: \(error.localizedDescription)"
            case .hotkeyUnavailable(let reason):
                return "The recording hotkey is unavailable: \(reason)"
            case .captureUnavailable(let reason):
                return "Audio capture is unavailable: \(reason)"
            case .internalError(let detail):
                return "An internal error occurred: \(detail)"
            }
        }
    }

    // MARK: - Public API

    /// Post a notification for the given category. Returns immediately; delivery is async.
    ///
    /// If `SettingsKey.notificationsEnabled` is stored as `false` in `UserDefaults`,
    /// this call is a no-op. If the current process does not have a valid bundle
    /// proxy (e.g. running from DerivedData via `swift run`), this call is also a
    /// silent no-op — the failure mode is logged to both `os.log` and `FileLogger`.
    public static func post(_ category: Category) {
        Task { @MainActor in
            await _post(category)
        }
    }

    // MARK: - Private helpers

    private static var isEnabled: Bool {
        // UserDefaults returns false for missing keys; registering a default ensures
        // first-launch behaviour is "enabled".
        let defaults = UserDefaults.standard
        defaults.register(defaults: [SettingsKey.notificationsEnabled.rawValue: true])
        return defaults.bool(forKey: SettingsKey.notificationsEnabled.rawValue)
    }

    /// Probe whether the running process has a valid bundle proxy. Cached after
    /// the first call. When `false`, all `UNUserNotificationCenter` access is
    /// suppressed to avoid the `bundleProxyForCurrentProcess == nil` assertion
    /// crash that occurs in non-bundled execution contexts.
    private static let hasBundleProxy: Bool = {
        // Heuristic: a proper .app bundle has a CFBundleIdentifier in Info.plist.
        // Test hosts and SPM binaries running from DerivedData do not.
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            return false
        }
        // Additional guard: the bundle path must end with .app for UNUserNotificationCenter
        // to accept it. Binaries launched directly from DerivedData (e.g. `swift run`)
        // have a Bundle.main whose bundleURL points at the binary's parent dir, not an .app.
        let bundlePath = Bundle.main.bundlePath
        return bundlePath.hasSuffix(".app") || bundlePath.hasSuffix(".appex")
    }()

    private static func _post(_ category: Category) async {
        guard isEnabled else {
            logger.debug("Notifications disabled — skipping post for '\(category.title)'.")
            return
        }

        guard hasBundleProxy else {
            // Crashing here used to occur because UNUserNotificationCenter.current()
            // asserts on a non-bundled process. Log and bail.
            logger.warning(
                "Notification suppressed (no bundle proxy): '\(category.title)' — \(category.body)"
            )
            FileLogger.shared.log(
                .warn,
                "AppNotifications: bundle proxy unavailable — suppressing '\(category.title)': \(category.body)"
            )
            return
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    logger.info("User declined notification authorization.")
                    return
                }
            } catch {
                logger.error("Notification auth request failed: \(error.localizedDescription)")
                FileLogger.shared.log(
                    .error,
                    "AppNotifications: auth request failed: \(error.localizedDescription)"
                )
                return
            }
        case .denied:
            logger.info("Notifications denied by user — skipping '\(category.title)'.")
            return
        default:
            break
        }

        let content = UNMutableNotificationContent()
        content.title = category.title
        content.body = category.body
        content.sound = .default

        let requestID = "com.whiskey.notification.\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: nil)

        do {
            try await center.add(request)
            logger.debug("Notification posted: '\(category.title)'")
        } catch {
            logger.error("Failed to post notification '\(category.title)': \(error.localizedDescription)")
            FileLogger.shared.log(
                .error,
                "AppNotifications: delivery failed for '\(category.title)': \(error.localizedDescription)"
            )
        }
    }
}
