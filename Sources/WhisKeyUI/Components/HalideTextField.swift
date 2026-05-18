import SwiftUI

// MARK: - HalideTextFieldModifier

/// Applies Halide design system styling to any `TextField`.
///
/// Usage: `TextField("Placeholder", text: $value).halideTextField()`
public struct HalideTextFieldModifier: ViewModifier {
    @FocusState private var focused: Bool

    public init() {}

    public func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.body)
            .foregroundColor(HalideTokens.textPrimary)
            .padding(.horizontal, HalideTokens.spacing8)
            .padding(.vertical, HalideTokens.spacing6)
            .background(HalideTokens.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: HalideTokens.radiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: HalideTokens.radiusMedium)
                    .stroke(
                        focused ? HalideTokens.accentAmber : HalideTokens.borderDefault,
                        lineWidth: focused ? 1.5 : 1
                    )
            )
            .focused($focused)
    }
}

// MARK: - View extension

extension View {
    /// Applies `HalideTextFieldModifier` to a `TextField`.
    public func halideTextField() -> some View {
        modifier(HalideTextFieldModifier())
    }
}
