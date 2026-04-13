import AppKit
import Foundation

/// Reads the frontmost application from `NSWorkspace` and derives an `InjectionContext`.
///
/// Also provides tone-style suggestions based on the active app's bundle identifier,
/// allowing the pipeline to select an appropriate `CleanupProfile` automatically.
public struct ContextService: Sendable {

    public init() {}

    // MARK: - Active context

    /// Returns an `InjectionContext` reflecting the currently frontmost application.
    ///
    /// Must be called from the main thread (NSWorkspace requirement).
    @MainActor
    public func currentContext() -> InjectionContext {
        let app = NSWorkspace.shared.frontmostApplication
        return InjectionContext(
            activeAppName: app?.localizedName ?? "Unknown",
            activeAppBundleID: app?.bundleIdentifier ?? "",
            focusedFieldContent: nil   // Accessibility read is handled downstream by TextInjector.
        )
    }

    // MARK: - Tone suggestion

    /// Returns the recommended `ToneStyle` for a given bundle identifier.
    ///
    /// This is a pure function — safe to call from any context.
    public func suggestedToneStyle(for bundleID: String) -> ToneStyle {
        switch bundleID {

        // Messaging / casual
        case "com.tinyspeck.slackmacgap",
             "com.apple.Messages":
            return .casual

        // Development / technical
        case "com.github.GitHubClient",
             "com.microsoft.VSCode",
             "com.apple.Terminal":
            return .technical

        // Documents / professional writing
        case "com.apple.mail",
             "notion.id",
             "com.microsoft.Word":
            return .professional

        default:
            return .casual
        }
    }
}
