import Testing
@testable import WhisKeyCore

struct PermissionsManagerTests {

    // MARK: - PermissionType enumeration

    @Test func permissionTypeRawValues() {
        #expect(PermissionType.microphone.rawValue == "Microphone")
        #expect(PermissionType.accessibility.rawValue == "Accessibility")
        #expect(PermissionType.inputMonitoring.rawValue == "Input Monitoring")
    }

    @Test func allCasesIncludesThreePermissions() {
        #expect(PermissionType.allCases.count == 3)
    }

    // MARK: - PermissionStatus enum completeness

    @Test func permissionStatusCasesExist() {
        let statuses: [PermissionStatus] = [.granted, .denied, .notDetermined, .restricted]
        #expect(statuses.count == 4)
    }

    // MARK: - Status checks

    @Test func statusMethodReturnsValidStatus() {
        let manager = PermissionsManager()
        let status = manager.status(for: .microphone)
        // Exhaustive switch — compile error if new case added without handling
        switch status {
        case .granted, .denied, .notDetermined, .restricted:
            break
        }
    }

    @Test func statusesReturnsAllThreePermissions() {
        let manager = PermissionsManager()
        let statuses = manager.statuses()
        #expect(statuses.count == 3)
        #expect(statuses.keys.contains(.microphone))
        #expect(statuses.keys.contains(.accessibility))
        #expect(statuses.keys.contains(.inputMonitoring))
    }

    @Test func allGrantedReturnsBool() {
        let manager = PermissionsManager()
        // Smoke test — exact value depends on system state
        _ = manager.allGranted()
    }

    // MARK: - Initialization

    @Test func managerInitializes() {
        _ = PermissionsManager()
    }

    // MARK: - Settings URL (UI side effects — skipped in automated runs)

    @Test(.disabled("Opens System Settings — manual verification only"))
    func openAccessibilitySettingsDoesNotCrash() {
        PermissionsManager().openAccessibilitySettings()
    }

    @Test(.disabled("Opens System Settings — manual verification only"))
    func openInputMonitoringSettingsDoesNotCrash() {
        PermissionsManager().openInputMonitoringSettings()
    }
}
