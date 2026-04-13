import Foundation

/// Snapshot of the focused UI context at the moment text injection is triggered.
public struct InjectionContext: Sendable {
    /// Display name of the frontmost application (e.g. "Safari").
    public let activeAppName: String

    /// Bundle ID of the frontmost application (e.g. "com.apple.Safari").
    public let activeAppBundleID: String

    /// Current string value of the focused text field, if readable via Accessibility API.
    /// Nil when the field is not accessible or not a text element.
    public let focusedFieldContent: String?

    public init(
        activeAppName: String,
        activeAppBundleID: String,
        focusedFieldContent: String?
    ) {
        self.activeAppName = activeAppName
        self.activeAppBundleID = activeAppBundleID
        self.focusedFieldContent = focusedFieldContent
    }
}
