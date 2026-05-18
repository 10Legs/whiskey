import SwiftUI

// MARK: - HalidePrimaryButtonStyle

/// Filled amber button for affirmative / add actions.
public struct HalidePrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundColor(HalideTokens.accentAmber)
            .padding(.horizontal, HalideTokens.spacing12)
            .padding(.vertical, HalideTokens.spacing6)
            .background(
                configuration.isPressed
                    ? HalideTokens.accentAmber.opacity(0.35)
                    : HalideTokens.accentAmberDim
            )
            .clipShape(RoundedRectangle(cornerRadius: HalideTokens.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: HalideTokens.radiusSmall)
                    .stroke(HalideTokens.accentAmberBorder, lineWidth: 1)
            )
    }
}

// MARK: - HalideSecondaryButtonStyle

/// Ghost button for cancel / secondary actions.
public struct HalideSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundColor(HalideTokens.textSecondary)
            .padding(.horizontal, HalideTokens.spacing12)
            .padding(.vertical, HalideTokens.spacing6)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: HalideTokens.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: HalideTokens.radiusSmall)
                    .stroke(
                        configuration.isPressed
                            ? HalideTokens.accentAmber
                            : HalideTokens.borderDefault,
                        lineWidth: 1
                    )
            )
    }
}

// MARK: - HalideDestructiveButtonStyle

/// Destructive action button (delete / remove).
public struct HalideDestructiveButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundColor(Color(nsColor: .systemRed))
            .padding(.horizontal, HalideTokens.spacing12)
            .padding(.vertical, HalideTokens.spacing6)
            .background(Color(nsColor: .systemRed).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: HalideTokens.radiusSmall))
            .overlay(
                RoundedRectangle(cornerRadius: HalideTokens.radiusSmall)
                    .stroke(Color(nsColor: .systemRed).opacity(0.35), lineWidth: 1)
            )
    }
}
