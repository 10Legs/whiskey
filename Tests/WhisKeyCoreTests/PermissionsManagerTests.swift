import XCTest
@testable import WhisKeyCore

class PermissionsManagerTests: XCTestCase {

    // MARK: - PermissionType enumeration

    func testPermissionTypeRawValues() {
        XCTAssertEqual(PermissionType.microphone.rawValue, "Microphone")
        XCTAssertEqual(PermissionType.accessibility.rawValue, "Accessibility")
        XCTAssertEqual(PermissionType.inputMonitoring.rawValue, "Input Monitoring")
    }

    func testAllCasesIncludesThreePermissions() {
        XCTAssertEqual(PermissionType.allCases.count, 3)
    }

    // MARK: - PermissionStatus enum completeness

    func testPermissionStatusCasesExist() {
        let statuses: [PermissionStatus] = [.granted, .denied, .notDetermined, .restricted]
        XCTAssertEqual(statuses.count, 4)
    }

    // MARK: - Status checks

    func testStatusMethodReturnsValidStatus() {
        let manager = PermissionsManager()
        let status = manager.status(for: .microphone)
        // Exhaustive switch — compile error if new case added without handling
        switch status {
        case .granted, .denied, .notDetermined, .restricted:
            break
        }
    }

    func testStatusesReturnsAllThreePermissions() {
        let manager = PermissionsManager()
        let statuses = manager.statuses()
        XCTAssertEqual(statuses.count, 3)
        XCTAssertTrue(statuses.keys.contains(.microphone))
        XCTAssertTrue(statuses.keys.contains(.accessibility))
        XCTAssertTrue(statuses.keys.contains(.inputMonitoring))
    }

    func testAllGrantedReturnsBool() {
        let manager = PermissionsManager()
        // Smoke test — exact value depends on system state
        _ = manager.allGranted()
    }

    // MARK: - Initialization

    func testManagerInitializes() {
        _ = PermissionsManager()
    }

    // MARK: - Settings URL (UI side effects — skipped in automated runs)

    // Disabled: Opens System Settings — manual verification only.
    func testOpenAccessibilitySettingsDoesNotCrash() throws {
        throw XCTSkip("Opens System Settings — manual verification only")
    }

    // Disabled: Opens System Settings — manual verification only.
    func testOpenInputMonitoringSettingsDoesNotCrash() throws {
        throw XCTSkip("Opens System Settings — manual verification only")
    }
}
