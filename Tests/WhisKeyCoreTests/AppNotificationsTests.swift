@testable import WhisKeyCore
import XCTest

@MainActor
class AppNotificationsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: SettingsKey.notificationsEnabled.rawValue)
    }

    func test_notificationCategory_modelMissingHasTitle() {
        let category = AppNotifications.Category.modelMissing
        XCTAssertEqual(category.title, "Whisper Model Missing")
    }

    func test_notificationCategory_modelMissingHasBody() {
        let category = AppNotifications.Category.modelMissing
        XCTAssertTrue(category.body.contains("Whisper model"))
        XCTAssertTrue(category.body.contains("Settings"))
    }

    func test_notificationCategory_downloadFailedIncludesError() {
        struct TestError: LocalizedError {
            var errorDescription: String? { "network timeout" }
        }
        let category = AppNotifications.Category.downloadFailed(TestError())
        XCTAssertEqual(category.title, "Download Failed")
        XCTAssertTrue(category.body.contains("network timeout"))
    }

    func test_notificationCategory_permissionDeniedIncludesDetail() {
        let category = AppNotifications.Category.permissionDenied("Microphone")
        XCTAssertEqual(category.title, "Permission Required")
        XCTAssertTrue(category.body.contains("Microphone"))
    }

    func test_notificationCategory_injectionFailedIncludesReason() {
        let category = AppNotifications.Category.injectionFailed("No focused element")
        XCTAssertEqual(category.title, "Text Injection Failed")
        XCTAssertTrue(category.body.contains("No focused element"))
    }

    func test_notificationCategory_transcriptionFailedIncludesError() {
        struct TestError: LocalizedError {
            var errorDescription: String? { "model load failed" }
        }
        let category = AppNotifications.Category.transcriptionFailed(TestError())
        XCTAssertEqual(category.title, "Transcription Failed")
        XCTAssertTrue(category.body.contains("model load failed"))
    }

    func test_notificationCategory_hotkeyUnavailableIncludesReason() {
        let category = AppNotifications.Category.hotkeyUnavailable("Input Monitoring denied")
        XCTAssertEqual(category.title, "Hotkey Unavailable")
        XCTAssertTrue(category.body.contains("Input Monitoring denied"))
    }

    func test_notificationCategory_captureUnavailableIncludesReason() {
        let category = AppNotifications.Category.captureUnavailable("Device disconnected")
        XCTAssertEqual(category.title, "Audio Capture Unavailable")
        XCTAssertTrue(category.body.contains("Device disconnected"))
    }

    func test_notificationCategory_internalErrorIncludesDetail() {
        let category = AppNotifications.Category.internalError("Unexpected nil in pipeline")
        XCTAssertEqual(category.title, "WhisKey Internal Error")
        XCTAssertTrue(category.body.contains("Unexpected nil in pipeline"))
    }

    func test_post_doesNotCrashWhenNotifications() {
        AppNotifications.post(.modelMissing)
    }
}
