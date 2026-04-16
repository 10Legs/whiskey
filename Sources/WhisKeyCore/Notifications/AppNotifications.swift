import Foundation
import os.log
import UserNotifications

private let logger = Logger(subsystem: "com.whiskey.app", category: "AppNotifications")

/// Fire-and-forget system notification facade for WhisKey pipeline errors.
///
/// All call sites are synchronous. Auth negotiation and delivery are handled
/// internally via a detached `Task`. Notification Center calls execute on the
/// main thread as required by `UNUserNotificationCenter`.
@MainActor
public enum AppNotifications {

    // MARK: - Category

    public enum Category {
        case modelMissing
        case downloadFailed(Error)
        case permissionDenied(String)
        case injectionFailed(String)
        case transcriptionFailed(Error)

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
            }
        }
    }

    // MARK: - Public API

    /// Post a notification for the given category. Returns immediately; delivery is async.
    ///
    /// If `SettingsKey.notificationsEnabled` is stored as `false` in `UserDefaults`,
    /// this call is a no-op. Authorization is requested on the first post if not yet determined.
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

    private static func _post(_ category: Category) async {
        guard isEnabled else {
            logger.debug("Notifications disabled — skipping post for '\(category.title)'.")
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
        }
    }
}
