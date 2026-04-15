import AppKit
import ApplicationServices
import AVFoundation

/// The set of system permissions WhisKey requires.
public enum PermissionType: String, CaseIterable, Sendable {
    case microphone      = "Microphone"
    case accessibility   = "Accessibility"
    case inputMonitoring = "Input Monitoring"
}

/// Authorization status for a single permission.
public enum PermissionStatus: Sendable {
    case granted
    case denied
    case notDetermined
    case restricted
}

/// Checks and requests the system permissions required by WhisKey.
///
/// All status checks run on the calling context; some (microphone request)
/// dispatch internally to a background thread per the AVFoundation contract.
public final class PermissionsManager: Sendable {

    public init() {}

    // MARK: - Public API

    /// Returns the current status of all required permissions.
    public func statuses() -> [PermissionType: PermissionStatus] {
        Dictionary(uniqueKeysWithValues: PermissionType.allCases.map { ($0, status(for: $0)) })
    }

    /// Returns true when all required permissions are granted.
    public func allGranted() -> Bool {
        PermissionType.allCases.allSatisfy { status(for: $0) == .granted }
    }

    /// Check a single permission without prompting.
    public func status(for permission: PermissionType) -> PermissionStatus {
        switch permission {
        case .microphone:
            return microphoneStatus()
        case .accessibility:
            return accessibilityStatus()
        case .inputMonitoring:
            return inputMonitoringStatus()
        }
    }

    /// Request Microphone permission.
    /// Calls `completion` on the main thread with the result.
    public func requestMicrophone(completion: @escaping @Sendable (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Open System Settings to the Accessibility pane.
    /// Users must grant this manually.
    public func openAccessibilitySettings() {
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Open System Settings to the Input Monitoring pane.
    public func openInputMonitoringSettings() {
        // swiftlint:disable:next force_unwrapping
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:       return .granted
        case .denied:           return .denied
        case .notDetermined:    return .notDetermined
        case .restricted:       return .restricted
        @unknown default:       return .notDetermined
        }
    }

    private func accessibilityStatus() -> PermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }

    private func inputMonitoringStatus() -> PermissionStatus {
        // CGPreflightListenEventAccess returns true when Input Monitoring is granted.
        CGPreflightListenEventAccess() ? .granted : .denied
    }
}
